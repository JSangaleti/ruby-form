#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative '../examples/curso'
require_relative '../examples/disciplina'
require_relative '../examples/aluno'

# Pode ser executado várias vezes: procura os registros antes de inserir.
def find_or_create(database, model, attributes, key)
  existing = database.all(model).find { |record| record.public_send(key) == attributes.fetch(key) }
  return existing if existing

  model.new(attributes).tap do |record|
    raise ArgumentError, record.errors.values.join(', ') unless record.save(database)
  end
end

path = ENV.fetch('RUBIFORM_DB', File.expand_path('../db/demo.sqlite3', __dir__))
FileUtils.mkdir_p(File.dirname(path))
database = Rubiform::Database.new(path)
begin
  database.prepare([Curso, Disciplina, Aluno])
  course = find_or_create(database, Curso, { nome: 'Ciência da Computação' }, :nome)
  first = find_or_create(database, Disciplina, { nome: 'Algoritmos', carga_horaria: 60 }, :nome)
  second = find_or_create(database, Disciplina, { nome: 'Linguagens de Programação', carga_horaria: 60 }, :nome)
  find_or_create(database, Aluno, { nome: 'Ana Silva', email: 'ana@example.com', curso_id: course.id,
                                   disciplina_ids: [first.id, second.id], turno: 'Noite' }, :email)
  find_or_create(database, Aluno, { nome: 'Bruno', email: 'bruno@example.com', curso_id: course.id,
                                   disciplina_ids: [first.id], turno: 'Noite' }, :email)
  puts "Dados de exemplo prontos em #{path}"
  puts "#{database.all(Curso).size} curso(s), #{database.all(Disciplina).size} disciplina(s), #{database.all(Aluno).size} aluno(s)."
ensure
  database.close
end
