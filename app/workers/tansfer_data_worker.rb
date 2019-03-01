class TansferDataWorker
  include Sidekiq::Worker
  include ValueConversions
  include ExternalApiHelper

  BATCH_SIZE =1000

  @@tables_read = {}
  @@tables_to_read = {}
  @@table_reflections_hash = {}
  def perform(service, master_db, prune_db)
    @@tables_read = {}
    @@tables_to_read = {}
    @@table_reflections_hash = {}
    final_tables_with_conditions = {}
    service_name = eval("DBPrune.#{service}_service_name")
    base_models_for_reflections = eval("DBPrune.#{service}_base_models_for_reflections")
    master_tables_for_prune = eval("DBPrune.#{service}_master_tables_for_prune")
    base_tables_for_prune = eval("DBPrune.#{service}_base_tables_for_prune")
    url = "http://#{service_name}/model_reflections?models=#{base_models_for_reflections}"
    @@table_reflections_hash = ExternalApiHelper.get_api_call(url)
    @@tables_to_read = master_tables_for_prune
    @@tables_to_read = @@tables_to_read.merge(base_tables_for_prune)
    final_tables_with_conditions = generate_final_tables_with_conditions(master_db) 
    prune_database(final_tables_with_conditions, master_db, prune_db)
  end
  def generate_final_tables_with_conditions(master_db) 
    while @@tables_to_read.any?
      table = @@tables_to_read.shift
      reflections_array = @@table_reflections_hash[table[0]].keys
      foreign_tables_keys = foreign_tables_keys_generator(reflections_array,table)
      store_to_tables_read([table[0],table[1]])
      if foreign_tables_keys.any?
        reflection_tables_foreign_keys_values_hash = update_tables_conditions(table[0], table[1], foreign_tables_keys, master_db)
        if reflection_tables_foreign_keys_values_hash.any?
          update_tables_to_read(reflection_tables_foreign_keys_values_hash)
        end
      end
    end
    return @@tables_read
  end
  def foreign_tables_keys_generator(reflections_array,table)
    foreign_tables_keys = {}
    reflections_array.each do |v|
      reflection_table = @@table_reflections_hash[table[0]][v]["table_name"]
      reflection_macro = @@table_reflections_hash[table[0]][v]["macro"]
      reflection_foreign_key = @@table_reflections_hash[table[0]][v]["foreign_key"]
      reflection_primary_key = @@table_reflections_hash[table[0]][v]["primary_key"]
      if !((@@tables_to_read.key?(reflection_table)&&@@tables_to_read[reflection_table].empty?)||(@@tables_read.key?(reflection_table)&&@@tables_read[reflection_table].empty?))
        case reflection_macro
        when "belongs_to" 
          keys={}
          keys.store("foreign_key",reflection_foreign_key)
          keys.store("primary_key",reflection_primary_key)
          foreign_tables_keys.store(reflection_table,keys)
        end
      end
    end
    return foreign_tables_keys
  end
  def update_tables_conditions(table_name, col_conditions = [], foreign_tables_keys = {}, master_db)
    foreign_key_values = []
    foreign_keys = []
    where_clause = where_clause_generator(col_conditions) 
    foreign_tables_keys.values.each do |keys|
      foreign_keys.push(keys["foreign_key"])
    end
    select_clause = select_clause_generator(foreign_keys)  
    db_master_conn = ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[master_db])
    sql_retrieve_foreign_key_value = "SELECT DISTINCT #{select_clause} FROM #{table_name} #{where_clause}" 
    foreign_key_values = db_master_conn.connection.exec_query(sql_retrieve_foreign_key_value).rows     
    if foreign_key_values.any?
      forgiegn_table_key_values = foreign_table_values(foreign_tables_keys,foreign_key_values)
      return forgiegn_table_key_values
    else
      return {}
    end
  end
  def foreign_table_values(foreign_tables_keys,foreign_key_values)
    col = []
    foreign_key_values[0].length.times do |j|
      foreign_key_values.length.times do |i|
        if !col.include?(foreign_key_values[i][j])
          col.push(foreign_key_values[i][j]) 
        end
      end
      foreign_key_values[j] = col
      col =[]
    end
    keys = foreign_tables_keys.keys
    keys.length.times do |i|
      foreign_tables_keys[keys[i]].store("values",foreign_key_values[i])
    end
    return foreign_tables_keys
  end
  def store_to_tables_read(table)
    flag = 0 #to know if a condition with that col is present or not
    if @@tables_read.key?(table[0]) 
      if @@tables_read[table[0]].any?
        @@tables_read[table[0]].length.times do |i|
          if table[1][0] == @@tables_read[table[0]][i][0]
            if table[1][0][1] == @@tables_read[table[0]][i][1]
              @@tables_read[table[0]][i][2].concat(table[1][2])
              flag = 1
              break
            end
          end
        end
        if flag == 0
          @@tables_read[table[0]].push(table[1])
        end
      end
    else
      @@tables_read.store(table[0],table[1])
    end
  end
  def update_tables_to_read(reflection_tables_foreign_keys_values_hash)
    reflection_tables_foreign_keys_values_hash.each do |key,value|
      table_master_read_flag = 0
      if value["values"].any?
        table_primary_key = value["primary_key"]
        if @@tables_read.key?(key)
          if @@tables_read[key].empty?
            table_master_read_flag = 1
          else
            @@tables_read[key].length.times do |i| 
              if @@tables_read[key][i][0] == table_primary_key && (@@tables_read[key][i][1] == "IN" || @@tables_read[key][i][1] == "=")
                value["values"] = value["values"] - @@tables_read[key][i][2]
                break
              end
            end
          end
        end
        if value["values"].any? && table_master_read_flag == 0
          if @@tables_to_read.key?(key)
            if @@tables_read[key].any?
              flag = 0 #to know if a condition with that col is present or not
              @@tables_to_read[key].length.times do |i| 
                if @@tables_to_read[key][i][0] == table_primary_key && (@@tables_to_read[key][i][1] == "IN" || @@tables_to_read[key][i][1] == "=")
                  @@tables_to_read[key][i][2] = value["values"]|@@tables_to_read[key][i][2]
                  @@tables_to_read[key][i][1] = "IN"
                  flag = 1
                  break
                end
              end
              if flag == 0
                @@tables_to_read[key].push([table_primary_key,"IN",value["values"],"OR"])
              end
            end
          else
            @@tables_to_read.store(key,[[table_primary_key,"IN",value["values"],"OR"]])
          end
        end        
      end 
    end
  end
  def prune_database(final_tables_with_conditions, master_db, prune_db)
    while final_tables_with_conditions.any?
      table = final_tables_with_conditions.shift
      prune_table(table[0], table[1], master_db, prune_db)
    end
  end
  def prune_table(table_name, col_conditions = [], master_db, prune_db) 
    offset = 0
    where_clause = where_clause_generator(col_conditions) 
    while true 
      db_master_conn = ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[master_db])
      sql_retrieve = "SELECT * FROM #{table_name} #{where_clause} ORDER BY 1 LIMIT #{BATCH_SIZE} OFFSET #{offset} "
      array_of_reterieved_key_value_hashes = db_master_conn.connection.exec_query(sql_retrieve).to_hash
      if array_of_reterieved_key_value_hashes.any?
        values = values_generator(array_of_reterieved_key_value_hashes)
        db_prune_conn = ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[prune_db])
        sql_insert =  "INSERT INTO #{table_name} VALUES #{values}"
        db_prune_conn.connection.exec_query(sql_insert)
      end
      if array_of_reterieved_key_value_hashes.length < BATCH_SIZE
        db_master_conn = ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations[master_db])
        break
      end
      offset = offset + BATCH_SIZE
    end
  end
end

 
