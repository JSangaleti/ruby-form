#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative '../models/curso'
require_relative '../models/disciplina'
require_relative '../models/aluno'

path = ENV.fetch('RUBIFORM_DB', File.expand_path('../db/demo.sqlite3', __dir__))
FileUtils.mkdir_p(File.dirname(path)) unless path == ':memory:'
database = Rubiform::Database.new(path)
app = Rubiform::App.new(models: [Curso, Disciplina, Aluno], database: database)
port = Integer(ENV.fetch('PORT', '4567'))
server = WEBrick::HTTPServer.new(Port: port, BindAddress: '127.0.0.1',
                               AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN))
server.mount('/', Rubiform::Servlet, app)
trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }
puts "Rubiform em http://127.0.0.1:#{port} (Ctrl+C encerra)"
puts "Banco: #{path}"
begin
  server.start
ensure
  database.close
end
