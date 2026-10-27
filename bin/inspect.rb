#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../examples/curso'
require_relative '../examples/disciplina'
require_relative '../examples/aluno'

database = Rubiform::Database.new(':memory:')
begin
  database.prepare([Curso, Disciplina, Aluno])
  course = Curso.new(nome: 'Computação')
  course.save(database)
  discipline = Disciplina.new(nome: 'Linguagens')
  discipline.save(database)
  student = Aluno.new(nome: 'Ana', email: 'ana@example.com', curso_id: course.id,
                     disciplina_ids: [discipline.id])
  student.save(database)
  puts "Aluno.class: #{Aluno.class}"
  puts "Aluno.superclass: #{Aluno.superclass}"
  puts "Campos: #{Aluno.fields.keys.inspect}"
  puts "Relações: #{Aluno.associations.keys.inspect}"
  puts "Chamada dinâmica: #{student.public_send(:nome)}"
  puts "Singleton class: #{Aluno.singleton_class}"
  puts "Curso do aluno: #{student.curso.nome}"
  puts "Alunos do curso: #{course.alunos.map(&:nome).join(', ')}"
  puts "Disciplinas do aluno: #{student.disciplinas.map(&:nome).join(', ')}"
  puts "Alunos da disciplina: #{discipline.alunos.map(&:nome).join(', ')}"
  puts "\nSQL gerado:\n#{database.schema_sql(Aluno, include_relations: true)}"
ensure
  database.close
end
