# frozen_string_literal: true

require_relative '../lib/rubiform'

class Produto < Rubiform::Model
  table :produtos
  title 'Produtos'

  field :nome, :text, label: 'Nome do produto', required: true, max_length: 80
  field :preco, :decimal, label: 'Preço (R$)', required: true, min: 0
  field :estoque, :integer, label: 'Estoque', required: true, min: 0
  field :categoria, :text, label: 'Categoria', as: :select,
        choices: ['Livros', 'Informática', 'Outros']
  field :disponivel, :boolean, label: 'Disponível'
end
