class GenerateSchemaWorker
  include Sidekiq::Worker
  require 'pg'
  require 'ruby_expect'

  def perform(master_db,prune_db)
    host_master = ActiveRecord::Base.configurations[master_db]["host"]
    port_master = ActiveRecord::Base.configurations[master_db]["port"]
    user_name_master = ActiveRecord::Base.configurations[master_db]["username"]
    password_master = ActiveRecord::Base.configurations[master_db]["password"]
    database_master = ActiveRecord::Base.configurations[master_db]["database"]
    dump_file = "#{database_master}.dump"
    host_prune = ActiveRecord::Base.configurations[prune_db]["host"]
    port_prune =  ActiveRecord::Base.configurations[prune_db]["port"]
    user_name_prune = ActiveRecord::Base.configurations[prune_db]["username"]
    password_prune = ActiveRecord::Base.configurations[prune_db]["password"]
    database_prune = ActiveRecord::Base.configurations[prune_db]["database"]
    exp = RubyExpect::Expect.spawn("pg_dump --host #{host_master}  --port #{port_master} --username #{user_name_master} --file #{dump_file} -s #{database_master}")
    exp.procedure do
      each do
        expect "Password:" do
          send password_master
        end
        expect /\$\s*$/ do
          send ""
        end
      end
    end
    exp = RubyExpect::Expect.spawn("createdb --host #{host_prune} --port #{port_prune} --username #{user_name_prune} #{database_prune}")
    exp.procedure do
      each do
        expect "Password:" do
          send password_prune
        end
        expect /\$\s*$/ do
          send ""
        end
      end 
    end
    exp = RubyExpect::Expect.spawn("psql -U #{user_name_prune} -d #{database_prune} -f #{dump_file}")
    exp.procedure do
      each do
        expect "Password for user #{user_name_prune}:" do
          send  password_prune
        end
        expect /\s*/ do
          send ""
        end
        expect /\$\s*$/ do
          send ""
        end
      end
    end
  end 
end
