# frozen_string_literal: true

module Rubiform
  # Mixin: comportamento compartilhado sem acrescentar outra classe ancestral.
  module Validation
    attr_reader :errors

    def valid?
      @errors = {}
      self.class.fields.each_value do |field|
        message = field.error(public_send(field.name))
        @errors[field.name] = "#{field.label} #{message}" if message
      end
      @errors.empty?
    end
  end
end
