# frozen_string_literal: true

require_relative '../lib/rubiform'

class Curso < Rubiform::Model
  table :cursos
  title 'Cursos'

  field :nome, :text, label: 'Nome do curso', required: true, max_length: 80
  has_many :alunos, model: -> { Aluno }, foreign_key: :curso_id, label: 'Alunos'
end
