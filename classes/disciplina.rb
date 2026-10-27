# frozen_string_literal: true

require_relative '../lib/rubiform'

class Disciplina < Rubiform::Model
  table :disciplinas
  title 'Disciplinas'

  field :nome, :text, label: 'Nome da disciplina', required: true, max_length: 80
  field :carga_horaria, :integer, label: 'Carga horária', min: 1
  many_to_many :alunos, model: -> { Aluno }, label: 'Alunos', ids: :aluno_ids,
               join_table: :alunos_disciplinas, foreign_key: :disciplina_id,
               association_key: :aluno_id
end
