# frozen_string_literal: true

module Rubiform
  class SchemaMismatch < StandardError; end

  # Executado dentro da transação de Database. Só faz mudanças aditivas.
  class Schema
    def initialize(connection)
      @connection = connection
    end

    def sql(model)
      raise ArgumentError, 'O modelo precisa ter ao menos um campo persistido' if model.stored_fields.empty?

      columns = ['"id" INTEGER PRIMARY KEY AUTOINCREMENT'] + model.stored_fields.map { |field| column_sql(field) }
      "CREATE TABLE IF NOT EXISTS #{quote(model.table)} (\n#{columns.map { |column| "  #{column}" }.join(",\n")}\n);"
    end

    def join_sql(owner, association)
      columns = [
        "#{quote(association.foreign_key)} INTEGER NOT NULL REFERENCES #{quote(owner.table)}(\"id\") ON DELETE CASCADE",
        "#{quote(association.association_key)} INTEGER NOT NULL REFERENCES #{quote(association.target.table)}(\"id\") ON DELETE CASCADE",
        "PRIMARY KEY (#{quote(association.foreign_key)}, #{quote(association.association_key)})"
      ]
      "CREATE TABLE IF NOT EXISTS #{quote(association.join_table)} (\n#{columns.map { |column| "  #{column}" }.join(",\n")}\n);"
    end

    def sync_model(model)
      @connection.execute(sql(model))
      actual = @connection.execute("PRAGMA table_info(#{quote(model.table)})")
      expected = model.stored_fields.to_h { |field| [field.name.to_s, field] }
      id = actual.find { |column| column['name'] == 'id' }
      mismatch!(model, 'chave primária diferente') unless id && id['type'] == 'INTEGER' && id['pk'] == 1
      actual.reject { |column| column['name'] == 'id' }.each do |column|
        field = expected[column['name']]
        unless field && field.sql_type == column['type'] && (field.required ? 1 : 0) == column['notnull']
          mismatch!(model, "remoção ou alteração de #{column['name']}")
        end
      end
      existing_names = actual.map { |column| column['name'] }
      validate_foreign_keys!(model, expected.select { |name, _| existing_names.include?(name) })
      expected.each_value do |field|
        next if existing_names.include?(field.name.to_s)

        if field.required && field.default.nil?
          mismatch!(model, "novo campo obrigatório #{field.name} precisa de default: para os registros antigos")
        end
        if field.is_a?(ReferenceField) && (!field.default.nil? || field.required)
          mismatch!(model, 'um novo vínculo em tabela existente deve começar opcional e sem default')
        end
        @connection.execute("ALTER TABLE #{quote(model.table)} ADD COLUMN #{column_sql(field)}")
      end
      model.stored_fields.grep(ReferenceField).each do |field|
        @connection.execute("CREATE INDEX IF NOT EXISTS #{quote("idx_#{model.table}_#{field.name}")} ON #{quote(model.table)} (#{quote(field.name)})")
      end
    end

    def sync_join(owner, association)
      @connection.execute(join_sql(owner, association))
      columns = @connection.execute("PRAGMA table_info(#{quote(association.join_table)})")
      expected = [association.foreign_key.to_s, association.association_key.to_s].sort
      unless columns.map { |column| column['name'] }.sort == expected &&
             columns.all? { |column| column['type'] == 'INTEGER' && column['notnull'] == 1 && column['pk'].positive? }
        raise SchemaMismatch, "Esquema incompatível na tabela intermediária #{association.join_table}"
      end
      expected_refs = {
        association.foreign_key.to_s => [owner.table, 'id', 'CASCADE'],
        association.association_key.to_s => [association.target.table, 'id', 'CASCADE']
      }
      unless foreign_keys(association.join_table) == expected_refs
        raise SchemaMismatch, "Chaves estrangeiras incompatíveis em #{association.join_table}"
      end
      # A PK atende buscas pela primeira chave; este índice atende a relação inversa.
      @connection.execute("CREATE INDEX IF NOT EXISTS #{quote("idx_#{association.join_table}_#{association.association_key}")} ON #{quote(association.join_table)} (#{quote(association.association_key)})")
    end

    def quote(identifier)
      value = identifier.to_s
      raise ArgumentError, 'Identificador SQL inválido' unless /\A[a-z][a-z0-9_]*\z/.match?(value)

      %Q("#{value}")
    end

    private

    def column_sql(field)
      sql = "#{quote(field.name)} #{field.sql_type}#{' NOT NULL' if field.required}"
      sql += " DEFAULT #{literal(field.dump(field.default))}" unless field.default.nil?
      if field.is_a?(ReferenceField)
        sql += " REFERENCES #{quote(field.association.target.table)}(\"id\") ON DELETE RESTRICT"
      end
      sql
    end

    def literal(value)
      return 'NULL' if value.nil?
      return value.to_s if value.is_a?(Numeric)

      "'#{value.to_s.gsub("'", "''")}'"
    end

    def foreign_keys(table)
      @connection.execute("PRAGMA foreign_key_list(#{quote(table)})").to_h do |fk|
        [fk['from'], fk.values_at('table', 'to', 'on_delete')]
      end
    end

    def validate_foreign_keys!(model, fields)
      expected = fields.values.grep(ReferenceField).to_h do |field|
        [field.name.to_s, [field.association.target.table, 'id', 'RESTRICT']]
      end
      mismatch!(model, 'alteração de relacionamentos existentes') unless foreign_keys(model.table) == expected
    end

    def mismatch!(model, reason)
      raise SchemaMismatch, "Não foi alterada a tabela #{model.table}: #{reason}. Os dados foram preservados."
    end
  end
end
