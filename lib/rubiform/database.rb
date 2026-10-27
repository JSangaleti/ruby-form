# frozen_string_literal: true

module Rubiform
  class Database
    def initialize(path)
      @connection = SQLite3::Database.new(path)
      @connection.results_as_hash = true
      @connection.busy_timeout = 3000
      @connection.execute('PRAGMA foreign_keys = ON')
      @schema = Schema.new(@connection)
      @mutex = Mutex.new
    end

    def prepare(models)
      validate_models!(models)
      @mutex.synchronize do
        @connection.transaction(:immediate) do
          models.each { |model| @schema.sync_model(model) }
          models.each do |model|
            model.associations.each_value do |association|
              @schema.sync_join(model, association) if association.kind == :many_to_many
            end
          end
          raise SchemaMismatch, 'Há referências inválidas no banco' unless @connection.execute('PRAGMA foreign_key_check').empty?
        end
      end
    end

    def create_table(model)
      @mutex.synchronize { @connection.transaction(:immediate) { @schema.sync_model(model) } }
    end

    def schema_sql(model, include_relations: false)
      result = @schema.sql(model)
      if include_relations
        model.associations.each_value do |association|
          result += "\n\n#{@schema.join_sql(model, association)}" if association.kind == :many_to_many
        end
      end
      result
    end

    # O registro e todos os vínculos N:N são gravados na mesma transação.
    def insert(record)
      @mutex.synchronize do
        inserted_id = nil
        @connection.transaction(:immediate) do
          check_references!(record)
          fields = record.class.stored_fields
          names = fields.map { |field| quote(field.name) }.join(', ')
          values = fields.map { |field| field.dump(record.public_send(field.name)) }
          sql = "INSERT INTO #{quote(record.class.table)} (#{names}) VALUES (#{(['?'] * fields.length).join(', ')})"
          @connection.execute(sql, values)
          id = @connection.last_insert_row_id
          inserted_id = id
          record.class.fields.values.grep(ManyIdsField).each do |field|
            association = field.association
            record.public_send(field.name).each do |target_id|
              @connection.execute("INSERT INTO #{quote(association.join_table)} (#{quote(association.foreign_key)}, #{quote(association.association_key)}) VALUES (?, ?)", [id, target_id])
            end
          end
        end
        inserted_id
      end
    end

    def all(model)
      @mutex.synchronize { rows_to_models(model, @connection.execute("SELECT * FROM #{quote(model.table)} ORDER BY id DESC")) }
    end

    def find(model, id)
      return nil if id.nil?

      @mutex.synchronize do
        row = @connection.get_first_row("SELECT * FROM #{quote(model.table)} WHERE id = ?", [id])
        row ? rows_to_models(model, [row]).first : nil
      end
    end

    def options(model, display)
      @mutex.synchronize do
        @connection.execute("SELECT id, #{quote(display)} AS label FROM #{quote(model.table)} ORDER BY #{quote(display)}, id").map do |row|
          [row['id'], row['label'].to_s]
        end
      end
    end

    def related(record, association)
      return association.kind == :belongs_to ? nil : [] unless record.id
      return find(association.target, record.public_send(association.foreign_key)) if association.kind == :belongs_to

      @mutex.synchronize do
        target = association.target
        rows = if association.kind == :has_many
                 @connection.execute("SELECT * FROM #{quote(target.table)} WHERE #{quote(association.foreign_key)} = ? ORDER BY id", [record.id])
               else
                 @connection.execute("SELECT target.* FROM #{quote(target.table)} AS target INNER JOIN #{quote(association.join_table)} AS links ON target.id = links.#{quote(association.association_key)} WHERE links.#{quote(association.foreign_key)} = ? ORDER BY target.id", [record.id])
               end
        rows_to_models(target, rows)
      end
    end

    def close
      @mutex.synchronize { @connection.close }
    end

    private

    def quote(identifier) = @schema.quote(identifier)

    def check_references!(record)
      record.class.fields.each_value do |field|
        next unless field.is_a?(ReferenceField) || field.is_a?(ManyIdsField)

        ids = Array(record.public_send(field.name)).compact
        exists = ids.all? do |id|
          @connection.get_first_value("SELECT 1 FROM #{quote(field.association.target.table)} WHERE id = ?", [id])
        end
        raise InvalidReference.new(field.name, "#{field.label}: selecione somente registros existentes") unless exists
      end
    end

    # Chamada apenas enquanto o mutex já está ocupado. Não percorre relações recursivamente.
    def rows_to_models(model, rows)
      rows.map do |row|
        attributes = model.stored_fields.to_h { |field| [field.name, field.load(row[field.name.to_s])] }
        model.fields.values.grep(ManyIdsField).each do |field|
          association = field.association
          attributes[field.name] = @connection.execute("SELECT #{quote(association.association_key)} AS target_id FROM #{quote(association.join_table)} WHERE #{quote(association.foreign_key)} = ? ORDER BY #{quote(association.association_key)}", [row['id']]).map { |link| link['target_id'] }
        end
        model.new(attributes).tap do |record|
          record.instance_variable_set(:@id, row['id'])
          record.instance_variable_set(:@database, self)
        end
      end
    end

    def validate_models!(models)
      raise ArgumentError, 'Informe ao menos um modelo' if models.empty?
      tables = models.map(&:table)
      raise ArgumentError, 'Tabelas repetidas' unless tables.uniq.size == tables.size

      joins = {}
      models.each do |owner|
        owner.associations.each_value do |association|
          target = association.target
          raise ArgumentError, "Registre também #{target} no App" unless models.include?(target)
          unless target.stored_fields.any? { |field| field.name == association.display }
            raise ArgumentError, "O campo de exibição #{association.display} não existe em #{target}"
          end
          if association.kind == :has_many
            inverse = target.fields[association.foreign_key]
            unless inverse.is_a?(ReferenceField) && inverse.association.target == owner
              raise ArgumentError, "#{owner}.#{association.name} precisa do belongs_to correspondente"
            end
          end
          next unless association.kind == :many_to_many
          raise ArgumentError, 'Tabela intermediária não pode ser uma tabela de modelo' if tables.include?(association.join_table)

          mapping = { association.foreign_key => owner.table, association.association_key => target.table }
          previous = joins[association.join_table]
          raise ArgumentError, "Declarações N:N incompatíveis em #{association.join_table}" if previous && previous != mapping

          joins[association.join_table] = mapping
        end
      end
    end
  end
end
