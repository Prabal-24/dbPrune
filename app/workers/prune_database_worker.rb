class PruneDatabaseWorker
  include Sidekiq::Worker

  def perform
    services_db_hash = DBPrune.services_db_hash
    services_db_hash.each do |service_name,db|
      GenerateSchemaWorker.new.perform(db["master_db"],db["prune_db"])
      TansferDataWorker.new.perform(service_name, db["master_db"], db["prune_db"])
    end
  end
end
