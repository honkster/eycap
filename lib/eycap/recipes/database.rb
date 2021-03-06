Capistrano::Configuration.instance(:must_exist).load do

  namespace :db do

    def extract_database_dot_yml
      run("cat #{shared_path}/config/database.yml") { |channel, stream, data| @environment_info = YAML.load(data)[rails_env] }
    end

    task :backup_name, :roles => :db, :only => { :primary => true } do
      now = Time.now
      run "mkdir -p #{shared_path}/db_backups"
      backup_time = [now.year,now.month,now.day,now.hour,now.min,now.sec].join('-')
      set :backup_file, "#{shared_path}/db_backups/#{environment_database}-snapshot-#{backup_time}.sql"
    end
  
    desc "Clone Production Database to Staging Database."
    task :clone_prod_to_staging, :roles => :db, :only => { :primary => true } do

      # This task currently runs only on traditional EY offerings.
      # You need to have both a production and staging environment defined in 
      # your deploy.rb file.  

      backup_name
      on_rollback { run "rm -f #{backup_file}" }
      extract_database_dot_yml

      if @environment_info['adapter'] == 'mysql'
        dbhost = @environment_info['host']
        dbuser = @environment_info['username']
        environment_database = @environment_info['database']
        dbhost = environment_dbhost.sub('-master', '') + '-replica' if dbhost != 'localhost' # added for Solo offering, which uses localhost
        dbpass = @environment_info['password']
        run "mysqldump --add-drop-table -u #{dbuser} -h #{dbhost} -p#{dbpass} #{environment_database} | bzip2 -c > #{backup_file}.bz2" do |ch, stream, out |
           ch.send_data "#{dbpass}\n" if out=~ /^Enter password:/
        end
        run "bzcat #{backup_file}.bz2 | mysql -u #{dbuser} -p -h #{staging_dbhost} #{staging_database}" do |ch, stream, out|
           ch.send_data "#{dbpass}\n" if out=~ /^Enter password:/
        end
      else
        run "pg_dump -W -c -U #{dbuser} -h #{production_dbhost} #{production_database} | bzip2 -c > #{backup_file}.bz2" do |ch, stream, out|
           ch.send_data "#{dbpass}\n" if out=~ /^Password:/
        end
        run "bzcat #{backup_file}.bz2 | psql -W -U #{dbuser} -h #{staging_dbhost} #{staging_database}" do |ch, stream, out|
           ch.send_data "#{dbpass}\n" if out=~ /^Password/
        end
      end
      run "rm -f #{backup_file}"
    end
  
    desc "Backup your MySQL or PostgreSQL database to shared_path+/db_backups"
    task :dump, :roles => :db, :only => {:primary => true} do
      backup_name
      extract_database_dot_yml
      if @environment_info['adapter'] == 'mysql'
        dbhost = @environment_info['host']
        dbhost = environment_dbhost.sub('-master', '') + '-replica' if dbhost != 'localhost' # added for Solo offering, which uses localhost
        dbuser = @environment_info['username']
        environment_database = @environment_info['database']
        dbpass = @environment_info['password']
        run "mysqldump --add-drop-table -u #{dbuser} -h #{dbhost} -p#{dbpass} #{environment_database} | bzip2 -c > #{backup_file}.bz2" do |ch, stream, out |
           ch.send_data "#{dbpass}\n" if out=~ /^Enter password:/
        end
      else
        run "pg_dump -W -c -U #{dbuser} -h #{environment_dbhost} #{environment_database} | bzip2 -c > #{backup_file}.bz2" do |ch, stream, out |
           ch.send_data "#{dbpass}\n" if out=~ /^Password:/
        end
      end
    end
    
    desc "Sync your production database to your local workstation"
    task :clone_to_local, :roles => :db, :only => {:primary => true} do
      backup_name
      dump
      get "#{backup_file}.bz2", "/tmp/#{application}.sql.gz"
      development_info = YAML.load_file("config/database.yml")['development']
      if development_info['adapter'] == 'mysql'
        run "bzcat /tmp/#{application}.sql.gz | mysql -u #{development_info['username']} -p -h #{development_info['host']} #{development_info['database']}" do |ch, stream, out |
          ch.send_data "#{development_info['password']}\n" if out=~ /Enter password:/
        end
      else
        run "bzcat /tmp/#{application}.sql.gz | psql -W -U #{development_info['username']} -h #{development_info['host']} #{development_info['database']}" do |ch, stream, out |
           ch.send_data "#{development_info['password']}\n" if out=~ /^Password/
        end
      end
    end
  end

end
