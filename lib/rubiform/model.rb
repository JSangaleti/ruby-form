# frozen_string_literal: true

module Rubiform
  class Model
    include Validation
    attr_reader :id

    class << self
      def table(name = nil)
        if name
          raise ArgumentError, 'Nome de tabela inválido' unless /\A[a-z][a-z0-9_]*\z/.match?(name.to_s)
          @table_name = name.to_s.freeze
        end
        @table_name || raise(ArgumentError, "Declare table na classe #{self}")
      end

      def title(value = nil)
        @title = value.to_s.freeze if value
        @title || name.to_s.split('::').last
      end

      def fields
        inherited = superclass.respond_to?(:fields) ? superclass.fields : {}
        inherited.merge(@fields || {}).freeze
      end

      def associations
        inherited = superclass.respond_to?(:associations) ? superclass.associations : {}
        inherited.merge(@associations || {}).freeze
      end

      def stored_fields = fields.values.select(&:persisted?)

      def field(name, type = :text, **options)
        kind = TYPES.fetch(type) { raise ArgumentError, "Tipo desconhecido: #{type}" }
        add_field(kind.new(name, **options))
      end

      def belongs_to(name, model:, label: nil, display: :nome, required: false)
        association = Association.new(name, kind: :belongs_to, model: model, label: label, display: display)
        assert_available!(association.name)
        add_field(ReferenceField.new(association.foreign_key, association: association,
                                     label: association.label, required: required))
        add_association(association)
      end

      def has_many(name, model:, foreign_key:, label: nil, display: :nome)
        add_association(Association.new(name, kind: :has_many, model: model,
                                       foreign_key: foreign_key, label: label, display: display))
      end

      def many_to_many(name, model:, join_table:, foreign_key:, association_key:,
                       ids: nil, label: nil, display: :nome, required: false)
        association = Association.new(name, kind: :many_to_many, model: model, join_table: join_table,
                                       foreign_key: foreign_key, association_key: association_key,
                                       ids: ids, label: label, display: display)
        assert_available!(association.name)
        add_field(ManyIdsField.new(association.ids_name, association: association,
                                   label: association.label, required: required))
        add_association(association)
      end

      private

      def assert_available!(name)
        if fields.key?(name.to_sym) || associations.key?(name.to_sym) ||
           instance_methods.include?(name.to_sym) || private_instance_methods.include?(name.to_sym)
          raise ArgumentError, "Campo ou relação reservado ou repetido: #{name}"
        end
      end

      def add_field(metadata)
        assert_available!(metadata.name)
        (@fields ||= {})[metadata.name] = metadata
        # O bloco captura metadata: cada método mantém o campo que deve acessar.
        define_method(metadata.name) do
          instance_variable_get("@#{metadata.name}")
        end
        define_method("#{metadata.name}=") do |value|
          converted = begin
            metadata.cast(value)
          rescue Field::InvalidValue
            value
          end
          instance_variable_set("@#{metadata.name}", converted)
        end
      end

      def add_association(association)
        assert_available!(association.name)
        (@associations ||= {})[association.name] = association
        define_method(association.name) do |database = @database|
          raise ArgumentError, 'Salve o objeto ou informe o banco para consultar a relação' unless database

          database.related(self, association)
        end
      end
    end

    def initialize(attributes = {})
      unknown = attributes.keys.map(&:to_s) - self.class.fields.keys.map(&:to_s)
      raise ArgumentError, "Campos desconhecidos: #{unknown.join(', ')}" unless unknown.empty?

      @errors = {}
      self.class.fields.each do |name, field|
        value = if attributes.key?(name)
                  attributes[name]
                elsif attributes.key?(name.to_s)
                  attributes[name.to_s]
                else
                  field.default
                end
        public_send("#{name}=", value)
      end
    end

    def attributes
      self.class.fields.keys.to_h { |name| [name, public_send(name)] }
    end

    def save(database)
      return false unless valid?
      raise ArgumentError, 'Este mini-ORM só insere registros novos' if id

      @id = database.insert(self)
      @database = database
      true
    rescue InvalidReference => e
      @errors[e.field_name] = e.message
      false
    end
  end
end
