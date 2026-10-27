# frozen_string_literal: true

module Rubiform
  class InvalidReference < StandardError
    attr_reader :field_name

    def initialize(field_name, message)
      @field_name = field_name
      super(message)
    end
  end

  # O Proc adia a resolução da constante, permitindo referências nos dois sentidos.
  class Association
    attr_reader :name, :label, :display, :foreign_key, :join_table, :association_key, :ids_name, :kind

    def initialize(name, kind:, model:, label: nil, display: :nome, foreign_key: nil,
                   join_table: nil, association_key: nil, ids: nil)
      @name = identifier(name).to_sym
      @kind, @target = kind, model
      @label = (label || name.to_s.capitalize).to_s.freeze
      @display = identifier(display).to_sym
      @foreign_key = identifier(foreign_key || "#{name}_id").to_sym
      @join_table = identifier(join_table).freeze if join_table
      @association_key = identifier(association_key).to_sym if association_key
      @ids_name = identifier(ids || "#{name}_ids").to_sym
      if kind == :many_to_many && (!@join_table || !@association_key || @foreign_key == @association_key)
        raise ArgumentError, 'N:N precisa de join_table e duas chaves diferentes'
      end
      freeze
    end

    def target
      klass = @target.respond_to?(:call) ? @target.call : @target
      raise ArgumentError, 'O destino da relação precisa herdar de Rubiform::Model' unless klass.is_a?(Class) && klass < Model

      klass
    end

    private

    def identifier(value)
      raise ArgumentError, "Identificador de relação inválido: #{value}" unless /\A[a-z][a-z0-9_]*\z/.match?(value.to_s)

      value.to_s
    end
  end

  class ReferenceField < IntegerField
    attr_reader :association

    def initialize(name, association:, **options)
      @association = association
      super(name, **options)
    end

    def default_widget = :reference
    def widgets = [:reference]
  end

  # Campo virtual: seus valores ficam na tabela intermediária, não em uma coluna.
  class ManyIdsField < Field
    attr_reader :association

    def initialize(name, association:, **options)
      @association = association
      super(name, **options)
    end

    def default_widget = :many
    def widgets = [:many]
    def persisted? = false
    def blank?(value) = value.nil? || value == []

    def cast(value)
      return [] if value.nil?
      raise InvalidValue, 'deve ser uma lista de identificadores' unless value.is_a?(Array)

      value.map do |id|
        raise InvalidValue, 'possui um identificador inválido' unless /\A[1-9]\d*\z/.match?(id.to_s)

        id.to_i
      end.uniq
    end

    def error(value)
      ids = cast(value)
      required && ids.empty? ? 'precisa ter ao menos uma seleção' : nil
    rescue InvalidValue => e
      e.message
    end

    def display(value) = Array(value).join(', ')
  end
end
