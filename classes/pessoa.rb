# frozen_string_literal: true

require_relative '../lib/rubiform'

class Pessoa < Rubiform::Model
  table :pessoas
  title 'Pessoas'

  field :nome, :text, label: 'Nome completo', required: true, max_length: 80
  field :email, :text, label: 'E-mail', as: :email, required: true
  field :idade, :integer, label: 'Idade', min: 0, max: 130
  field :nascimento, :date, label: 'Data de nascimento'
  field :curso, :text, label: 'Curso', as: :select, required: true,
        choices: ['Ciência da Computação', 'Engenharia', 'Outro']
  field :turno, :text, label: 'Turno', as: :radio,
        choices: ['Manhã', 'Tarde', 'Noite']
  field :bolsista, :boolean, label: 'Bolsista'
  field :observacoes, :text, label: 'Observações', as: :textarea, max_length: 300
end
