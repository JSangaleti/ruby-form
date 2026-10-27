# frozen_string_literal: true

module Rubiform
  # Cada objeto Field reúne os metadados de um atributo do modelo.
  class Field
    class InvalidValue < StandardError; end

    attr_reader :name, :label, :required, :widget, :choices, :minimum, :maximum, :max_length, :default

    def initialize(name, label: nil, required: false, as: nil, choices: nil,
                   min: nil, max: nil, max_length: nil, default: nil)
      raise ArgumentError, 'Nome de campo inválido' unless /\A[a-z][a-z0-9_]*\z/.match?(name.to_s)

      @name = name.to_sym
      @label = (label || name.to_s.tr('_', ' ').capitalize).dup.freeze
      @required = required
      @widget = as || default_widget
      @choices = Array(choices).map { |choice| choice.to_s.dup.freeze }.freeze
      @minimum, @maximum, @max_length = min, max, max_length
      raise ArgumentError, "Controle inválido: #{@widget}" unless widgets.include?(@widget)
      if %i[select radio].include?(@widget) && (@choices.empty? || @choices.any?(&:empty?))
        raise ArgumentError, 'Seleção precisa de opções não vazias'
      end
      @default = default.nil? ? nil : cast(default)
      if !default.nil? && (message = error(@default))
        raise ArgumentError, "Valor padrão de #{name}: #{message}"
      end
      @default.freeze unless @default.nil?
      freeze
    end

    def default_widget = :text
    def widgets = %i[text email textarea select radio]
    def sql_type = 'TEXT'
    def persisted? = true

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end

    def cast(value)
      blank?(value) ? nil : value.to_s
    end

    def error(value)
      return 'é obrigatório' if required && blank?(value)
      return if blank?(value)

      cast(value)
      return 'não está entre as opções permitidas' if %i[select radio].include?(widget) && !choices.include?(value.to_s)
      return "deve ter no máximo #{max_length} caracteres" if max_length && value.to_s.length > max_length
      return 'deve ser um e-mail válido' if widget == :email && !/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/.match?(value.to_s)

      nil
    rescue InvalidValue => e
      e.message
    end

    def dump(value) = cast(value)
    def display(value) = value.nil? ? '' : value.to_s
    def load(value) = cast(value)
  end

  class IntegerField < Field
    def default_widget = :number
    def widgets = [:number]
    def sql_type = 'INTEGER'

    def cast(value)
      return nil if blank?(value)
      return value if value.is_a?(Integer)
      raise InvalidValue, 'deve ser um número inteiro' unless /\A[+-]?\d+\z/.match?(value.to_s)

      Integer(value.to_s, 10)
    end

    def error(value)
      basic = super
      return basic if basic || blank?(value)

      number = cast(value)
      return "deve ser no mínimo #{minimum}" if minimum && number < minimum
      return "deve ser no máximo #{maximum}" if maximum && number > maximum

      nil
    end
  end

  class DecimalField < IntegerField
    def sql_type = 'REAL'

    def cast(value)
      return nil if blank?(value)

      number = Float(value.to_s)
      raise InvalidValue, 'deve ser um número decimal finito' unless number.finite?

      number
    rescue ArgumentError, TypeError
      raise InvalidValue, 'deve ser um número decimal'
    end
  end

  class BooleanField < Field
    def default_widget = :checkbox
    def widgets = [:checkbox]
    def sql_type = 'INTEGER'

    def cast(value)
      return true if [true, 1, '1', 'true', 'on'].include?(value)
      return false if [false, nil, '', 0, '0', 'false', 'off'].include?(value)

      raise InvalidValue, 'deve ser verdadeiro ou falso'
    end

    def error(value)
      boolean = cast(value)
      required && !boolean ? 'precisa ser marcado' : nil
    rescue InvalidValue => e
      e.message
    end

    def dump(value) = cast(value) ? 1 : 0
    def display(value) = cast(value) ? 'Sim' : 'Não'
  end

  class DateField < Field
    def default_widget = :date
    def widgets = [:date]

    def cast(value)
      return nil if blank?(value)
      return value if value.is_a?(Date)

      date = Date.iso8601(value.to_s)
      raise InvalidValue, 'deve ser uma data no formato AAAA-MM-DD' unless date.iso8601 == value.to_s

      date
    rescue ArgumentError
      raise InvalidValue, 'deve ser uma data válida no formato AAAA-MM-DD'
    end

    def dump(value) = cast(value)&.iso8601
  end

  TYPES = { text: Field, integer: IntegerField, decimal: DecimalField,
            boolean: BooleanField, date: DateField }.freeze
end
