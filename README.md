# Rubiform

Mini-framework em Ruby para criar e listar cadastros. A definição de uma classe
orienta a geração do formulário HTML, das tabelas SQLite e dos relacionamentos.

Esta versão inclui **1:N, N:N e acréscimo automático de campos**. A demonstração
principal usa Cursos, Disciplinas e Alunos. Pessoas e Produtos permanecem em
`examples/` como exemplos simples e nos testes de compatibilidade.

## 1. Instalar no Linux Mint / Ubuntu

Extraia o ZIP em uma pasta nova. Abra a pasta `rubiform` que contém este README,
clique com o botão direito e escolha **Abrir no terminal**.

Instale as ferramentas do sistema uma vez:

```bash
sudo apt update
sudo apt install ruby-full ruby-bundler build-essential libsqlite3-dev
ruby -v
bundle -v
```

O projeto usa Ruby 3.1 ou superior e foi verificado em Ruby 3.2.3. Depois:

```bash
bundle config set --local path vendor/bundle
bundle install
bundle exec ruby bin/test.rb
bundle exec ruby bin/server.rb
```

Abra **http://127.0.0.1:4567**. Ctrl+C encerra o servidor.
Depois da instalação das gems, a demonstração funciona sem internet.
Se `bundle` não existir, verifique se sua instalação disponibiliza `bundle3.2`.

## 2. Usar a aplicação

1. Em **Cursos**, cadastre `Ciência da Computação`.
2. Em **Disciplinas**, cadastre `Algoritmos` e `Linguagens de Programação`.
   Não é necessário selecionar alunos nessa etapa: essa seleção é opcional.
3. Em **Alunos**, informe nome e e-mail, escolha o curso e marque as disciplinas.
4. Salve. A listagem mostra os nomes do curso e das disciplinas.
5. Abra Cursos e Disciplinas: suas listagens também mostram os alunos vinculados.

Para demonstrar N:N, cadastre Ana em duas disciplinas e Bruno em uma disciplina
que Ana também selecionou. Assim, há vários alunos por disciplina e várias
disciplinas por aluno.

### Preencher exemplos automaticamente (opcional)

Antes de iniciar o servidor, ou em outro terminal na mesma pasta:

```bash
bundle exec ruby bin/seed.rb
```

Esse comando cria um curso, duas disciplinas e dois alunos. Pode ser executado
novamente sem repetir os exemplos já encontrados. Ele não apaga registros.

## 3. Comprovar a inclusão dinâmica de um campo

1. Cadastre alunos normalmente.
2. Encerre o servidor com Ctrl+C.
3. Abra `examples/aluno.rb` e acrescente **dentro da classe, antes do último `end`**:

```ruby
field :telefone, :text, label: 'Telefone'
```

4. Execute novamente:

```bash
bundle exec ruby bin/server.rb
```

5. Recarregue a página de Alunos. O campo Telefone aparecerá no formulário e na
   listagem. Os registros antigos e seus relacionamentos continuam no mesmo banco.

Não é necessário alterar HTML, SQL ou arquivos do framework. O reinício carrega
a definição modificada da classe e acrescenta a coluna que falta.

Para um campo simples novo que seja obrigatório, informe um padrão válido:

```ruby
field :situacao, :text, label: 'Situação', required: true, default: 'Ativo'
```

Esse valor preenche a nova coluna dos registros antigos e aparece nos formulários
novos. Sem `default:`, o framework recusa essa mudança e mantém o banco anterior.

Uma demonstração automatizada desse mecanismo, em banco temporário separado:

```bash
bundle exec ruby bin/demo_migration.rb
```

## 4. Relações declaradas nos modelos

Em Aluno:

```ruby
belongs_to :curso, model: -> { Curso }, label: 'Curso', required: true

many_to_many :disciplinas, model: -> { Disciplina },
             label: 'Disciplinas', ids: :disciplina_ids,
             join_table: :alunos_disciplinas,
             foreign_key: :aluno_id, association_key: :disciplina_id
```

Em Curso:

```ruby
has_many :alunos, model: -> { Aluno }, foreign_key: :curso_id, label: 'Alunos'
```

Em Disciplina há outra declaração `many_to_many`, com as chaves invertidas e a
mesma tabela intermediária. Isso permite criar o vínculo pelo cadastro de um
aluno ou pelo cadastro de uma nova disciplina.

Depois de salvar ou carregar os objetos:

```ruby
aluno.curso
curso.alunos
aluno.disciplinas
disciplina.alunos
```

O banco recebe uma chave estrangeira `curso_id` em alunos e uma tabela
`alunos_disciplinas` com uma linha por vínculo. O campo Ruby `disciplina_ids` é
virtual: não vira uma string com IDs dentro de uma coluna.

O `-> { Curso }` é uma lambda que adia a consulta à constante. Isso permite
referências nos dois sentidos sem depender de definir uma classe dentro da outra.
Os modelos usados em relações precisam estar registrados no App.

## 5. Banco e mudanças de esquema

O padrão é `db/demo.sqlite3`. Reiniciar o servidor usa o mesmo arquivo.

Para escolher outro arquivo ou outra porta:

```bash
RUBIFORM_DB=db/ensaio.sqlite3 PORT=4568 bundle exec ruby bin/server.rb
```

O framework acrescenta campos opcionais, campos simples com padrões válidos,
tabelas novas e tabelas intermediárias novas, dentro de uma transação. Ele não
remove colunas, não muda seus tipos e não muda a obrigatoriedade de colunas
existentes automaticamente. Reordenar os campos no código é permitido.

Um novo `belongs_to` numa tabela existente deve começar opcional e sem padrão.
O framework não adivinha a que curso cada registro antigo deveria pertencer.
Um relacionamento obrigatório desse tipo precisa de uma migração de dados
específica antes de impor a obrigatoriedade.

Se já tiver usado a versão anterior, preserve seu arquivo SQLite antes de
substituir os arquivos do projeto. As tabelas Pessoas e Produtos não são apagadas;
a nova demonstração apenas passa a usar Cursos, Disciplinas e Alunos.

## 6. Organização e recursos da linguagem

| Arquivo | Responsabilidade |
| --- | --- |
| `field.rb` | Tipos, metadados, padrões e validação dos campos |
| `association.rb` | Metadados das relações e campos de referência/seleção múltipla |
| `model.rb` | DSL, herança, acessores e métodos de relacionamento dinâmicos |
| `validation.rb` | Mixin de validação |
| `schema.rb` | Geração de SQL e mudanças aditivas de esquema |
| `database.rb` | Persistência, consultas, relações e transações |
| `form.rb` | HTML e opções consultadas nas tabelas relacionadas |
| `app.rb` | Rotas genéricas, leitura de formulários e listagens |
| `examples/` | Modelos da aplicação, separados do framework |
| `test/` | Testes de comportamento e integração HTTP |

Para mostrar reflexão e as relações no terminal:

```bash
bundle exec ruby bin/inspect.rb
```

Leia `docs/GUIA_ESTUDO.md` e `docs/DEMONSTRACAO.md`. O roteiro de oito minutos
foi atualizado para apresentar Ruby, código e aplicação, sem depender de slides.
Os slides antigos não acompanham este pacote porque descreviam a versão sem relações.

## 7. Dependências e escopo

Não foram acrescentadas gems nesta atualização. Permanecem:

- `webrick`: servidor HTTP.
- `sqlite3`: adaptador de acesso ao SQLite.
- `minitest`: testes, sem participar da aplicação.

Formulários, ORM, relações, validação e mudanças de esquema são implementados no
projeto. Não há Rails, ActiveRecord nem gerador de formulários de terceiros.
A regra do professor sobre permitir os adaptadores HTTP e SQLite ainda não foi
confirmada. Esta versão **não é uma implementação sem gems**.

O escopo inclui criar e listar. Não há edição ou exclusão pela interface.
As mudanças automáticas de esquema são aditivas, e não uma ferramenta geral de
migrações. A aplicação escuta em `127.0.0.1` e não possui login.
O exemplo de campo decimal usa Float/REAL. Dados financeiros exigiriam uma
representação com precisão adequada, como centavos inteiros.

## Referências

- Enunciado e aulas de Aspectos de Linguagens de Programação, Prof. Rodrigo Hübner.
- Ruby Module: https://docs.ruby-lang.org/en/3.2/Module.html
- Ruby Object: https://docs.ruby-lang.org/en/3.2/Object.html
- SQLite ALTER TABLE: https://www.sqlite.org/lang_altertable.html
- SQLite Foreign Keys: https://www.sqlite.org/foreignkeys.html
- Adaptador sqlite3: https://sparklemotion.github.io/sqlite3-ruby/
