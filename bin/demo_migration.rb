#!/usr/bin/env ruby
# frozen_string_literal: true

require 'tmpdir'
require_relative '../lib/rubiform'

# Duas versões de um modelo apontam para a mesma tabela. O banco é temporário.
original = Class.new(Rubiform::Model) do
  table :contatos
  field :nome, :text, required: true
end
changed = Class.new(Rubiform::Model) do
  table :contatos
  field :nome, :text, required: true
  field :telefone, :text, label: 'Telefone'
  field :situacao, :text, required: true, default: 'Ativo'
end

Dir.mktmpdir('rubiform-migracao') do |directory|
  path = File.join(directory, 'demo.sqlite3')
  first = Rubiform::Database.new(path)
  begin
    first.prepare([original])
    record = original.new(nome: 'Ana')
    record.save(first)
    id = record.id
    puts "Antes: #{first.find(original, id).attributes.inspect}"
  ensure
    first.close
  end
  second = Rubiform::Database.new(path)
  begin
    second.prepare([changed])
    record = second.find(changed, id)
    raise 'O registro antigo não foi preservado' unless record.nome == 'Ana' && record.id == id
    raise 'O novo padrão não foi aplicado' unless record.situacao == 'Ativo'

    html = Rubiform::Form.new(changed.new, action: '/contatos', token: 'demo').render
    raise 'O novo campo não apareceu' unless html.include?('name="telefone"')

    puts "Depois: #{record.attributes.inspect}"
    puts 'OK: o mesmo banco manteve o registro e ganhou os novos campos e o formulário.'
  ensure
    second.close
  end
end
