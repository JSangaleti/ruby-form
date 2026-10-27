# frozen_string_literal: true

require 'webrick'
require 'securerandom'

module Rubiform
  class Servlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, app)
      super(server)
      @app = app
    end

    def service(request, response) = @app.call(request, response)
  end

  # O servidor entrega HTTP ao App. App usa os mesmos metadados para qualquer modelo.
  class App
    class BadForm < StandardError; end

    def initialize(models:, database:)
      @models = models.to_h { |model| ["/#{model.table}", model] }.freeze
      raise ArgumentError, 'Tabelas repetidas' unless @models.size == models.size

      @database = database
      @token = SecureRandom.hex(32)
      database.prepare(models)
    end

    def call(request, response)
      response['Content-Type'] = 'text/html; charset=utf-8'
      response['Cache-Control'] = 'no-store'
      response['X-Content-Type-Options'] = 'nosniff'
      response['Content-Security-Policy'] = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
      unless %w[localhost 127.0.0.1].include?(request.host)
        return reply(response, 403, 'Host não permitido')
      end
      if request.path == '/' && request.request_method == 'GET'
        response.status = 303
        response['Location'] = @models.keys.first
        return response.body = ''
      end
      model = @models[request.path]
      return reply(response, 404, 'Página não encontrada') unless model

      case request.request_method
      when 'GET'
        response.body = page(model, model.new, saved: request.query['saved'] == '1')
      when 'POST'
        begin
          attributes, token = parse_form(request, model)
        rescue BadForm => e
          return reply(response, 400, e.message)
        end
        return reply(response, 403, 'Token de formulário inválido. Recarregue a página.') unless token == @token

        record = model.new(attributes)
        if record.save(@database)
          response.status = 303 # POST/Redirect/GET evita novo INSERT ao atualizar a página.
          response['Location'] = "#{request.path}?saved=1"
          response.body = ''
        else
          response.status = 422
          response.body = page(model, record)
        end
      else
        response['Allow'] = 'GET, POST'
        reply(response, 405, 'Método não permitido')
      end
    end

    private

    def parse_form(request, model)
      unless request['content-type'].to_s.split(';').first == 'application/x-www-form-urlencoded'
        raise BadForm, 'Envie um formulário no formato esperado'
      end
      params = CGI.parse(request.body.to_s).to_h do |key, values|
        [key.dup.force_encoding(Encoding::UTF_8), values.map { |value| value.dup.force_encoding(Encoding::UTF_8) }]
      end
      params.each do |key, values|
        unless key.valid_encoding? && values.all?(&:valid_encoding?)
          raise BadForm, 'O formulário precisa usar UTF-8 válido'
        end
      end
      raise BadForm, 'Token repetido' if params.fetch('_csrf', []).length > 1

      attributes = model.fields.to_h do |name, field|
        if field.is_a?(ManyIdsField)
          raise BadForm, 'Use uma lista para seleções múltiplas' if params.key?(name.to_s)

          [name, params.fetch("#{name}[]", [])]
        else
          values = params.fetch(name.to_s, [])
          raise BadForm, 'Campo simples repetido ou recebido como lista' if values.length > 1 || params.key?("#{name}[]")

          [name, values.first]
        end
      end
      [attributes, params.fetch('_csrf', []).first]
    end

    def h(value) = Form.escape(value)

    def reply(response, status, text)
      response.status = status
      response.body = "<!doctype html><html lang=\"pt-BR\"><meta charset=\"utf-8\"><title>Rubiform</title><p>#{h(text)}</p></html>"
    end

    def page(model, record, saved: false)
      nav = @models.map do |path, klass|
        %Q(<a href="#{h(path)}"#{' aria-current="page"' if klass == model}>#{h(klass.title)}</a>)
      end.join
      errors = record.errors.empty? ? '' : '<p class="notice bad" role="alert">Confira os campos indicados. O registro não foi salvo.</p>'
      notice = saved ? '<p class="notice" role="status">Cadastro salvo no SQLite.</p>' : ''
      form = Form.new(record, action: "/#{model.table}", token: @token, database: @database).render
      records = @database.all(model)
      columns = model.fields.values + model.associations.values.select { |association| association.kind == :has_many }
      headings = columns.map { |field| "<th scope=\"col\">#{h(field.label)}</th>" }.join
      rows = records.map do |item|
        cells = columns.map { |column| "<td>#{h(display_value(item, column))}</td>" }.join
        "<tr><td>#{item.id}</td>#{cells}</tr>"
      end.join
      relationships = model.associations.values.map do |association|
        type = association.kind == :many_to_many ? 'N:N' : '1:N'
        "<li>#{h(association.label)} (#{type})</li>"
      end.join
      <<~HTML
        <!doctype html>
        <html lang="pt-BR">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{h(model.title)} - Rubiform</title><style>#{style}</style></head>
        <body><header><a class="brand" href="/">rubiform<span>Ruby + HTML + SQLite</span></a><nav aria-label="Cadastros">#{nav}</nav></header>
        <main><div class="intro"><p class="eyebrow">MINI-FRAMEWORK EM RUBY</p><h1>#{h(model.title)}</h1>
        <p>Formulário e tabela gerados a partir de uma classe.</p></div>
        #{notice}#{errors}<div class="layout"><section class="sheet"><h2>Novo cadastro</h2>#{form}</section>
        <aside><h2>Uma definição, duas saídas</h2><p>Os campos do modelo orientam a geração do HTML e das colunas do banco.</p>
        <dl><dt>Classe</dt><dd>#{h(model.name)}</dd><dt>Tabela</dt><dd>#{h(model.table)}</dd><dt>Campos</dt><dd>#{model.fields.size}</dd></dl>
        #{relationships.empty? ? '' : "<h2>Relacionamentos</h2><ul>#{relationships}</ul>"}
        <details><summary>SQL gerado pelo framework</summary><pre>#{h(@database.schema_sql(model, include_relations: true))}</pre></details></aside></div>
        <section class="records"><h2>Cadastros salvos <span>(#{records.length})</span></h2>
        #{records.empty? ? '<p class="empty">Nenhum cadastro ainda. Preencha o formulário para começar.</p>' : "<div class=\"table-wrap\"><table><thead><tr><th scope=\"col\">ID</th>#{headings}</tr></thead><tbody>#{rows}</tbody></table></div>"}
        </section></main><footer>Aspectos de Linguagens de Programação · UTFPR</footer></body></html>
      HTML
    end

    def display_value(record, column)
      if column.is_a?(ReferenceField)
        related = record.public_send(column.association.name)
        related ? related.public_send(column.association.display) : 'Não informado'
      elsif column.is_a?(ManyIdsField)
        record.public_send(column.association.name).map { |item| item.public_send(column.association.display) }.join(', ')
      elsif column.is_a?(Association)
        record.public_send(column.name).map { |item| item.public_send(column.display) }.join(', ')
      else
        column.display(record.public_send(column.name))
      end
    end

    def style
      <<~CSS
        *{box-sizing:border-box}body{margin:0;background:#f7f6f3;color:#272827;font:16px/1.5 system-ui,sans-serif}header{background:#fff;border-bottom:1px solid #e4e0d9;padding:22px max(24px,calc((100vw - 1120px)/2));display:flex;justify-content:space-between;align-items:center;gap:24px}.brand{text-decoration:none;font-size:25px;font-weight:800;letter-spacing:-1px;color:#a52d36}.brand span{display:block;font-size:11px;font-weight:500;letter-spacing:1px;color:#777}nav{display:flex;gap:20px;flex-wrap:wrap}nav a{color:#555;text-decoration:none;padding:6px 0}nav a[aria-current]{color:#a52d36;border-bottom:2px solid #a52d36}main{max-width:1120px;margin:auto;padding:40px 24px}.eyebrow{font-size:11px;letter-spacing:2px;font-weight:700;color:#a52d36}h1{font-size:38px;letter-spacing:-1px;line-height:1.2;margin:10px 0}h2{font-size:20px;letter-spacing:-.4px;margin:0 0 22px}.intro{margin-bottom:32px}.intro>p:last-child{color:#73736e}.layout{display:grid;grid-template-columns:minmax(0,1.5fr) minmax(0,1fr);gap:48px}.sheet{padding:28px;background:#fff;border:1px solid #e3dfd7;border-radius:8px}.field,fieldset{margin:0 0 19px}label,legend{font-size:14px;font-weight:600}label{display:block;margin-bottom:7px}input:not([type=radio]):not([type=checkbox]),select,textarea{display:block;width:100%;padding:11px 12px;border:1px solid #ccc8c0;border-radius:5px;background:#fff;font:inherit;color:#272827}input:focus,select:focus,textarea:focus{outline:2px solid #a52d36;outline-offset:2px}fieldset{padding:0;border:0}legend{margin-bottom:7px}.option{display:inline-flex;gap:8px;align-items:center;margin:0 16px 8px 0;font-weight:400}input[type=checkbox],input[type=radio]{accent-color:#a52d36;width:17px;height:17px}button{background:#a52d36;color:white;border:0;border-radius:5px;padding:13px 22px;font:600 15px system-ui;cursor:pointer}.hint{font-size:12px;color:#777;margin:16px 0 0}.error{color:#ac1d27;font-size:13px;margin:7px 0}[aria-invalid=true]{border-color:#ac1d27!important}.notice{padding:14px 18px;border-left:3px solid #46765f;background:#e8f0ea;margin-bottom:24px}.notice.bad{border-color:#a52d36;background:#f7e8e8}aside{padding-top:14px;color:#63635d}aside h2{color:#272827}dl{display:grid;grid-template-columns:100px 1fr;margin:28px 0}dt,dd{padding:7px 0;margin:0;font-size:14px}dd{font-weight:600;color:#333}summary{cursor:pointer;color:#a52d36;font-size:14px;font-weight:600}pre{font-size:12px;white-space:pre-wrap;overflow-wrap:anywhere;background:#ece9e3;padding:16px;border-radius:5px}.records{margin-top:48px}.records h2 span{font-weight:400;color:#888}.table-wrap{overflow:auto;border:1px solid #e3dfd7;border-radius:6px}table{border-collapse:collapse;width:100%;background:#fff;text-align:left;font-size:13px}th,td{padding:13px 16px;border-bottom:1px solid #eee;white-space:nowrap}th{background:#efece5;color:#666;font-weight:600}td{max-width:280px;overflow-wrap:anywhere;white-space:normal}.empty{color:#777;background:#eeece6;padding:24px;border-radius:6px}footer{max-width:1120px;margin:0 auto;padding:20px 24px 35px;color:#888;font-size:12px}@media(max-width:760px){.layout{grid-template-columns:1fr;gap:24px}header{align-items:flex-start;flex-direction:column;gap:12px}.brand span{max-width:140px}main{padding-top:24px}h1{font-size:30px}.sheet{padding:20px}}
      CSS
    end
  end
end
