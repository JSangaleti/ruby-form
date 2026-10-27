# frozen_string_literal: true

require_relative '../lib/rubiform'

class Aluno < Rubiform::Model
  table :alunos
  title 'Alunos'

  field :nome, :text, label: 'Nome completo', required: true, max_length: 80
  field :email, :text, label: 'E-mail', as: :email, required: true
  field :idade, :integer, label: 'Idade', min: 0, max: 130
  field :turno, :text, label: 'Turno', as: :radio,
        choices: ['Manhã', 'Tarde', 'Noite']
  field :bolsista, :boolean, label: 'Bolsista'
  field :observacoes, :text, label: 'Observações', as: :textarea, max_length: 300

  belongs_to :curso, model: -> { Curso }, label: 'Curso', required: true
  many_to_many :disciplinas, model: -> { Disciplina }, label: 'Disciplinas', ids: :disciplina_ids,
               join_table: :alunos_disciplinas, foreign_key: :aluno_id,
               association_key: :disciplina_id
end
