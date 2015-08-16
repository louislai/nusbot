require 'addressable/uri'
require 'anybase'
require 'digest'
require 'httparty'
require 'json'
require 'redis'
require 'yaml'

module NUSBotgram
  class Core
    CONFIG = YAML.load_file("lib/config/config.yml")
    API_ENDPOINT = 'http://api.nusmods.com'
    REDIRECT_ENDPOINT = 'https://nusmods.com/redirect.php?timetable='

    def initialize
      @@redis = Redis.new(:host => CONFIG[2][:REDIS_HOST], :port => CONFIG[2][:REDIS_PORT], :password => CONFIG[2][:REDIS_PASSWORD], :db => CONFIG[2][:REDIS_DB_DEFAULT])
    end

    private

    def callback(uri)
      uri_regex = /^(http|https).\/\/modsn.us\/*/i
      noredirect_regex = /^(http|https).\/\/nusmods.com\/timetable\/*/i

      modsn = uri.match uri_regex
      nusmods = uri.match noredirect_regex

      if !modsn && nusmods
        mods = decode_uri(uri)

        [0, mods]
      elsif modsn && !nusmods
        _uri = REDIRECT_ENDPOINT + uri

        # Resolve NUSMods Shortened link
        response = HTTParty.get(_uri)
        result = response.body
        json_result = JSON.parse(result)

        # Retrieve the actual resolved link
        redirect_url = json_result["redirectedUrl"]
        resolved_url = CGI::unescape(redirect_url)

        mods = decode_uri(resolved_url)

        [1, mods]
      elsif !modsn && !nusmods
        404
      end
    end

    private

    def decode_uri(uri)
      mods = Hash.new

      decoded = Addressable::URI.parse(uri)
      mods_query = decoded.query_values

      mods_query.each do |key, value|
        mods[key] = value
      end

      mods
    end

    private

    def get_uri_code(nusmods_uri)
      code = Addressable::URI.parse(nusmods_uri).path[1, 9]

      code
    end

    public

    def analyze_uri(uri)
      response = HTTParty.get(uri)

      case response.code
        when 200
          response.code
        when 403
          response.code
        when 404
          response.code
        when 500...600
          response.code
      end
    end

    public

    def db_exist(telegram_id)
      @@redis.hget("users", telegram_id)
    end

    private

    def find_keys(hash_key)
      keys = @@redis.keys("#{hash_key}:*")

      keys
    end

    private

    def ldelete_keys(hash_key)
      keys = find_keys(hash_key)
      key_len = keys.size

      for i in 0...key_len do
        len = @@redis.llen(keys[i])

        for j in 0...len do
          @@redis.rpop(keys[i])
        end
      end
    end

    private

    # If different NUSMods is sent, delete all the existing modules, then store the new modules.
    def delete_hmods(hash_key)
      results = @@redis.hgetall(hash_key)

      results.each do |key, value|
        @@redis.hdel(hash_key, key)
      end
    end

    public

    def get_mod(telegram_id)
      @@redis.select(0)
      modules_ary = Array.new

      uri_code = @@redis.hget("users", telegram_id)
      hash_key = "users:#{telegram_id}.#{uri_code}"

      if !uri_code
        404
      else
        keys = find_keys(hash_key)
        key_len = keys.size

        for i in 0...key_len do
          len = @@redis.llen(keys[i])

          for j in 0...len do
            modules_ary.push(@@redis.lindex(keys[i], j))
          end
        end
      end

      modules_ary
    end

    public

    def set_mod(uri, start_year, end_year, sem, *args)
      @@redis.select(0)
      telegram_id = args[0]
      user_code = db_exist(telegram_id)
      is_deleted = false

      modules = callback(uri)

      if modules[0] == 0
        uri_code = Anybase::Base62.random(5)

        modules[1].each do |key, value|
          unfreeze_key = key.dup
          code_query = /[a-zA-Z]{2,3}[\s]?[\d]{4}[a-zA-Z]{0,2}/
          module_code = key.match code_query
          module_type = unfreeze_key.sub!(code_query, "")[1, 3]

          response = HTTParty.get("#{API_ENDPOINT}/#{start_year}-#{end_year}/#{sem}/modules/#{module_code}.json")
          result = response.body
          is_deleted = preprocess_store(telegram_id, user_code, is_deleted, uri, uri_code, result, value, module_type)
        end
      elsif modules[0] == 1
        uri_code = get_uri_code(uri)

        modules[1].each do |key, value|
          unfreeze_key = key.dup
          code_query = /[a-zA-Z]{2,3}[\s]?[\d]{4}[a-zA-Z]{0,2}/
          module_code = key.match code_query
          module_type = unfreeze_key.sub!(code_query, "")[1, 3]

          response = HTTParty.get("#{API_ENDPOINT}/#{start_year}-#{end_year}/#{sem}/modules/#{module_code}.json")
          result = response.body
          is_deleted = preprocess_store(telegram_id, user_code, is_deleted, uri, uri_code, result, value, module_type)
        end
      else
        404
      end
    end

    private

    def preprocess_store(telegram_id, user_code, is_deleted, uri, uri_code, result, value, module_type)
      json_result = JSON.parse(result)

      mod_code = json_result["ModuleCode"]
      mod_title = json_result["ModuleTitle"]
      exam_date = json_result["ExamDate"]
      timetable = json_result["Timetable"]
      lecture_periods = json_result["LecturePeriods"]
      tutorial_periods = json_result["TutorialPeriods"]

      timetable.each do |_key|
        class_no = _key["ClassNo"]
        lesson_type = _key["LessonType"]
        week_text = _key["WeekText"]
        day_text = _key["DayText"]
        start_time = _key["StartTime"]
        end_time = _key["EndTime"]
        venue = _key["Venue"]

        hash_key = "users:#{telegram_id}.#{uri_code}"

        if !user_code
          # Customized JSON hash
          # Replace JSON hash with `_key` returns the same result
          if class_no.eql?(value) && lesson_type[0, 3].upcase.eql?(module_type)
            @@redis.hset("users", telegram_id, uri_code)
            store_json(hash_key, uri, mod_code, mod_title, exam_date, class_no, week_text, day_text, start_time, end_time, venue, lecture_periods, lesson_type, tutorial_periods)
          end
        else
          # Customized JSON hash
          # Replace JSON hash with `_key` returns the same result
          if class_no.eql?(value) && lesson_type[0, 3].upcase.eql?(module_type) ||
              "#{lesson_type[0].upcase}LEC".eql?("DLEC") ||
              "#{lesson_type[0].upcase}LEC".eql?("PLEC") ||
              "#{lesson_type[0].upcase}TUT".eql?("PTUT")

            hkey = "users:#{telegram_id}.#{user_code}"

            # Check if the same NUSMods URI shortened code exists,
            # If it does, do nothing, else delete and replace with the new NUSMods URI shortened code
            if user_code != uri_code && !is_deleted
              ldelete_keys(hkey)
              @@redis.hset("users", telegram_id, uri_code)
              is_deleted = true

              store_json(hash_key, uri, mod_code, mod_title, exam_date, class_no, week_text, day_text, start_time, end_time, venue, lecture_periods, lesson_type, tutorial_periods)
            elsif user_code == uri_code && !is_deleted
              ldelete_keys(hkey)
              @@redis.hset("users", telegram_id, uri_code)
              is_deleted = true

              store_json(hash_key, uri, mod_code, mod_title, exam_date, class_no, week_text, day_text, start_time, end_time, venue, lecture_periods, lesson_type, tutorial_periods)
            else
              store_json(hash_key, uri, mod_code, mod_title, exam_date, class_no, week_text, day_text, start_time, end_time, venue, lecture_periods, lesson_type, tutorial_periods)
            end
          end
        end
      end

      is_deleted
    end

    private

    def store_json(hash_key, uri, mod_code, mod_title, exam_date, class_no, week_text, day_text, start_time, end_time, venue, lecture_periods, lesson_type, tutorial_periods)
      @@redis.rpush("#{hash_key}:#{mod_code}", [:uri => uri,
                                                :module_code => mod_code,
                                                :module_title => mod_title,
                                                :exam_date => exam_date,
                                                :class_no => class_no,
                                                :week_text => week_text,
                                                :lesson_type => lesson_type,
                                                :day_text => day_text,
                                                :start_time => start_time,
                                                :end_time => end_time,
                                                :venue => venue,
                                                :lecture_periods => lecture_periods,
                                                :tutorial_periods => tutorial_periods].to_json)
    end

    private

    def get_active_users
      @@redis.select(0)
      keys = @@redis.hkeys("users")

      keys
    end

    private

    def get_all_history_users(db)
      @@redis.select(db)
      keys = @@redis.keys("users:history:*")
      n_users = Array.new

      keys.each do |key|
        n_users.push key.sub(/users:history:/, '').chomp('-logs')
      end

      n_users
    end

    public

    def get_all_users(db)
      n_users = get_all_history_users(db)
      users = get_active_users

      # Union of 2 array sets
      union = set_union(n_users, users)

      union
    end

    public

    def identify_idle_users(db)
      n_users = get_all_history_users(db)
      users = get_active_users

      # Differences of 2 array sets
      difference = set_difference(n_users, users)

      difference
    end

    public

    def get_state_transactions(telegram_id, command)
      @@redis.select(0)
      last_state = @@redis.hget("users:state:#{telegram_id}", command)

      last_state
    end

    public

    def save_state_transactions(telegram_id, command, state, *args)
      @@redis.select(0)
      @@redis.hmset("users:state:#{telegram_id}", command, state, *args)
    end

    public

    def remove_state_transactions(telegram_id, command)
      @@redis.select(0)
      @@redis.hdel("users:state:#{telegram_id}", command)
    end

    public

    def save_last_transaction(telegram_id, state)
      @@redis.select(0)
      @@redis.rpush("users:last_state:#{telegram_id}", state)
    end

    public

    def peek_last_transaction(telegram_id)
      @@redis.select(0)
      peeked_state = @@redis.rpop("users:last_state:#{telegram_id}")
      @@redis.rpush("users:last_state:#{telegram_id}", peeked_state)

      peeked_state
    end

    public

    def cancel_last_transaction(telegram_id)
      @@redis.select(0)
      @@redis.rpop("users:last_state:#{telegram_id}")
    end

    public

    def save_message_history(telegram_id, database, chat_id, message_id, from_user_first, from_user_last, from_user_username, user_id, message_date, message)
      @@redis.select(database)
      @@redis.lpush("users:history:#{telegram_id}-logs",
                    [:chat_id => chat_id,
                     :message_id => message_id,
                     :user_first => from_user_first,
                     :user_last => from_user_last,
                     :username => from_user_username,
                     :userid => user_id,
                     :message_date => message_date,
                     :message => message].to_json)
    end

    public

    def get_location(database, location_code)
      @@redis.select(database)
      @@redis.hget("mapnus:locations:#{location_code}", location_code)
    end

    public

    def location_exist(database, location_code)
      @@redis.select(database)
      @@redis.exists("mapnus:locations:#{location_code}")
    end

    public

    def get_alert_transactions(telegram_id, unix_timestamp)
      @@redis.select(0)
      alert_state = @@redis.hget("users:alerts:#{telegram_id}", unix_timestamp)

      alert_state
    end

    public

    def get_alert_state(telegram_id)
      @@redis.select(0)
      unix_timestamp = @@redis.lpop("users:alerts:state-#{telegram_id}")

      unix_timestamp
    end

    public

    def save_alert_transactions(telegram_id, message_id, task, *args)
      @@redis.select(0)
      # save_alert_state(telegram_id, message_id)
      @@redis.hmset("users:alerts:#{telegram_id}", message_id, task, *args)
      @@redis.hset("alerts", telegram_id, message_id)
    end

    public

    def save_alert_state(telegram_id, unix_timestamp)
      @@redis.select(0)
      @@redis.rpush("users:alerts:state-#{telegram_id}", unix_timestamp)
    end

    public

    def remove_alert_transactions(telegram_id, message_id)
      @@redis.select(0)
      @@redis.hdel("users:alerts:#{telegram_id}", message_id)
    end

    public

    def remove_alert_state(telegram_id)
      @@redis.select(0)
      @@redis.rpop("users:alerts:state-#{telegram_id}")
    end

    public

    def sort_alert_state(telegram_id, limit = 5)
      @@redis.select(0)
      sorted = @@redis.sort("users:alerts:state-#{telegram_id}", :limit => [0, limit], :order => "asc")

      sorted
    end

    public

    def remove_alerts(telegram_id, count = 0, unix_timestamp)
      @@redis.select(0)
      @@redis.lrem("users:alerts:state-#{telegram_id}", count, unix_timestamp)
    end

    public

    def check_daytime(time)
      if time[0, 2].to_i >= 0 && time[0, 2].to_i <= 11
        return 0
      elsif time[0, 2].to_i >= 12 && time[0, 2].to_i <= 17
        return 1
      elsif time[0, 2].to_i >= 18 && time[0, 2].to_i <= 24
        return 2
      end
    end

    private

    def set_union(set_a, set_b)
      union = set_a | set_b

      union
    end

    private

    def set_intersect(set_a, set_b)
      intersection = set_a & set_b

      intersection
    end

    private

    def set_difference(set_a, set_b)
      difference = set_a - set_b

      difference
    end
  end
end