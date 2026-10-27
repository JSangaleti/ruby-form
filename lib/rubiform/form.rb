# frozen_string_literal: true

module Rubiform
  class Form
    def self.escape(value) = CGI.escapeHTML(value.to_s)

    def initialize(record, action:, token:, database: nil)
      @record, @action, @token, @database = record, action, token, database
    end

    def render
      fields = @record.class.fields.values.map { |field| render_field(field) }.join("\n")
      <<~HTML
        <form method="post" action="#{h(@action)}" novalidate>
          <input type="hidden" name="_csrf" value="#{h(@token)}">
          #{fields}
          <button type="submit">Salvar cadastro</button>
          <p class="hint">* Campo obrigatório. Os dados são validados no servidor.</p>
        </form>
      HTML
    end

    private

    def h(value) = self.class.escape(value)

    def render_field(field)
      value = @record.public_send(field.name)
      message = @record.errors[field.name]
      error = message ? %Q(<p class="error" id="error_#{field.name}">#{h(message)}</p>) : ''
      required = field.required ? ' *' : ''
      control = control_for(field, value, message)
      if %i[radio checkbox many].include?(field.widget)
        %Q(<fieldset><legend>#{h(field.label)}#{required}</legend>#{control}#{error}</fieldset>)
      else
        %Q(<div class="field"><label for="#{field.name}">#{h(field.label)}#{required}</label>#{control}#{error}</div>)
      end
    end

    def related_options(field)
      raise ArgumentError, 'Informe database: para gerar campos de relacionamento' unless @database

      @database.options(field.association.target, field.association.display)
    end

    def relation_hint(field, options)
      return '' unless options.empty?

      target = field.association.target
      if field.is_a?(ManyIdsField) && !field.required
        return %Q(<p class="hint">Nenhuma opção cadastrada. Esta seleção é opcional.</p>)
      end
      %Q(<p class="hint">Nenhuma opção cadastrada. <a href="/#{h(target.table)}">Cadastre #{h(target.title.downcase)} primeiro</a>.</p>)
    end

    def control_for(field, value, message)
      attrs = %(name="#{field.name}" id="#{field.name}")
      attrs += ' required' if field.required
      attrs += %( aria-invalid="true" aria-describedby="error_#{field.name}") if message
      case field.widget
      when :reference
        options = related_options(field)
        choices = options.map do |id, label|
          selected = id.to_s == value.to_s ? ' selected' : ''
          %Q(<option value="#{id}"#{selected}>#{h(label)}</option>)
        end.join
        %Q(<select #{attrs}><option value="">Selecione</option>#{choices}</select>) + relation_hint(field, options)
      when :many
        options = related_options(field)
        selected = Array(value).map(&:to_s)
        choices = options.map do |id, label|
          checked = selected.include?(id.to_s) ? ' checked' : ''
          %Q(<label class="option"><input type="checkbox" name="#{field.name}[]" value="#{id}"#{checked}> #{h(label)}</label>)
        end.join
        choices + relation_hint(field, options)
      when :textarea
        %Q(<textarea #{attrs} rows="3">#{h(value)}</textarea>)
      when :checkbox
        checked = value == true ? ' checked' : ''
        # Uma checkbox desmarcada não aparece no POST. Model trata nil como false.
        %Q(<label class="option"><input type="checkbox" #{attrs} value="1"#{checked}> Sim</label>)
      when :select
        options = field.choices.map do |choice|
          selected = choice == value.to_s ? ' selected' : ''
          %Q(<option value="#{h(choice)}"#{selected}>#{h(choice)}</option>)
        end.join
        %Q(<select #{attrs}><option value="">Selecione</option>#{options}</select>)
      when :radio
        field.choices.each_with_index.map do |choice, index|
          checked = choice == value.to_s ? ' checked' : ''
          %Q(<label class="option"><input type="radio" name="#{field.name}" id="#{field.name}_#{index}" value="#{h(choice)}"#{checked}#{' required' if field.required}> #{h(choice)}</label>)
        end.join
      else
        attrs += %( min="#{h(field.minimum)}") if field.minimum
        attrs += %( max="#{h(field.maximum)}") if field.maximum
        attrs += %( maxlength="#{h(field.max_length)}") if field.max_length
        attrs += ' step="any"' if field.is_a?(DecimalField)
        %Q(<input type="#{field.widget}" #{attrs} value="#{h(value)}">)
      end
    end
  end
end
