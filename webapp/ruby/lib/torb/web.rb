require 'json'
require 'sinatra/base'
require 'erubi'
require 'mysql2'
require 'mysql2-cs-bind'
# require 'rack-mini-profiler'
module Torb
  class Web < Sinatra::Base
    # use Rack::MiniProfiler
    configure :development do
      require 'sinatra/reloader'
      register Sinatra::Reloader
    end

    set :root, File.expand_path('../..', __dir__)
    set :sessions, key: 'torb_session', expire_after: 3600
    set :session_secret, 'tagomoris'
    set :protection, frame_options: :deny

    set :erb, escape_html: true

    set :login_required, ->(value) do
      condition do
        if value && !get_login_user
          halt_with_error 401, 'login_required'
        end
      end
    end

    set :admin_login_required, ->(value) do
      condition do
        if value && !get_login_administrator
          halt_with_error 401, 'admin_login_required'
        end
      end
    end

    before '/api/*|/admin/api/*' do
      content_type :json
    end

    helpers do
      def db
        Thread.current[:db] ||= Mysql2::Client.new(
          host: '172.31.32.40',
          port: ENV['DB_PORT'],
          username: 'isucon',
          password: 'isucon',
          database: 'torb',
          database_timezone: :utc,
          cast_booleans: true,
          reconnect: true,
          init_command: 'SET SESSION sql_mode="STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION"',
        )
      end

      def get_events(where = nil)
        where ||= ->(e) { e['public_fg'] }

        db.query('BEGIN')
        begin
          event_list = db.query('SELECT * FROM events ORDER BY id ASC').select(&where).to_a
          events = get_event_detail(event_list).map do |event|
            event['sheets'].each { |sheet| sheet.delete('detail') }
            event
          end
          db.query('COMMIT')
        rescue
          db.query('ROLLBACK')
        end

        events
      end

      def get_event_detail(events, login_user_id = nil)
        return [] if events.empty?
        event_ids = events.map { |e| e['id'] }

        # zero fill
        sheets = db.query('SELECT * FROM sheets ORDER BY `rank`, num').to_a
        reservations = db.xquery("SELECT * FROM reservations WHERE event_id IN (#{event_ids.join(',')}) AND not_canceled GROUP BY event_id, sheet_id HAVING reserved_at = MIN(reserved_at)").map do |row|
          ["#{row['event_id']}_#{row['sheet_id']}", row]
        end.to_h

        events.map do |event|
          event['total']   = 0
          event['remains'] = 0
          event['sheets'] = {}
          %w[S A B C].each do |rank|
            event['sheets'][rank] = { 'total' => 0, 'remains' => 0, 'detail' => [] }
          end
          event
        end

        events.each do |event|
          sheets.each do |sheet|
            event['sheets'][sheet['rank']]['price'] ||= event['price'] + sheet['price']
            event['total'] += 1
            event['sheets'][sheet['rank']]['total'] += 1
            #reservation = reservation_event[sheet['id']]
            key = "#{event['id']}_#{sheet['id']}"
            reservation = reservations[key]
            if reservation
              sheet['mine']        = true if login_user_id && reservation['user_id'] == login_user_id
              sheet['reserved']    = true
              sheet['reserved_at'] = reservation['reserved_at'].to_i
            else
              event['remains'] += 1
              event['sheets'][sheet['rank']]['remains'] += 1
            end

            event['sheets'][sheet['rank']]['detail'].push(sheet)
          end

          event['public'] = event.delete('public_fg')
          event['closed'] = event.delete('closed_fg')
          event
        end
        sheets.each do |sheet|
          sheet.delete('id')
          sheet.delete('price')
          sheet.delete('rank')
        end

        events
      end

      def sanitize_event(event)
        sanitized = event.dup  # shallow clone
        sanitized.delete('price')
        sanitized.delete('public')
        sanitized.delete('closed')
        sanitized
      end

      def get_login_user
        user_id = session[:user_id]
        return unless user_id
        return session[:user] if session[:user]
        db.xquery('SELECT id, nickname FROM users WHERE id = ?', user_id).first
      end

      def get_login_administrator
        administrator_id = session['administrator_id']
        return unless administrator_id
        return session[:admin] if session[:admin]
        db.xquery('SELECT id, nickname FROM administrators WHERE id = ? LIMIT 1', administrator_id).first
      end

      def get_sheet(sheet_id)
        s_rank_num = 50
        a_rank_num = 200
        b_rank_num = 500
        c_rank_num = 1000
        rank = 'S'
        num = 0
        price = 0
        if sheet_id <= s_rank_num
          rank = 'S'
          num = sheet_id - 0
          price = 5000
        elsif sheet_id <= a_rank_num
          rank = 'A'
          num = sheet_id - s_rank_num
          price = 3000
        elsif sheet_id <= b_rank_num
          rank = 'B'
          num = sheet_id - a_rank_num
          price = 1000
        else sheet_id <= c_rank_num
          rank = 'C'
          num = sheet_id - b_rank_num
          price = 0
        end
        {
          rank: rank,
          num: num,
          price: price
        }
      end

      def get_total_sheet_from_rank(rank)
        case rank
        when 'S'
          return 50
        when 'A'
          return 150
        when 'B'
          return 300
        when 'C'
          return 500
        else
          return 0
        end
      end

      def validate_rank(rank)
        # db.xquery('SELECT COUNT(*) AS total_sheets FROM sheets WHERE `rank` = ?', rank).first['total_sheets'] > 0
        get_total_sheet_from_rank(rank) > 0
      end

      def body_params
        @body_params ||= JSON.parse(request.body.tap(&:rewind).read)
      end

      def halt_with_error(status = 500, error = 'unknown')
        halt status, { error: error }.to_json
      end

      def render_report_csv(reports)
        # reports = reports.sort_by { |report| report[:sold_at] }

        keys = %i[reservation_id event_id rank num price user_id sold_at canceled_at]
        body = keys.join(',')
        body << "\n"
        reports.each do |report|
          body << report.values_at(*keys).join(',')
          body << "\n"
        end

        headers({
          'Content-Type'        => 'text/csv; charset=UTF-8',
          'Content-Disposition' => 'attachment; filename="report.csv"',
        })
        body
      end
    end

    get '/' do
      @user   = get_login_user
      @events = get_events.map(&method(:sanitize_event))
      erb :index
    end

    get '/initialize' do
      system "../../db/init.sh"

      status 204
    end

    post '/api/users' do
      nickname   = body_params['nickname']
      login_name = body_params['login_name']
      password   = body_params['password']

      db.query('BEGIN')
      begin
        duplicated = db.xquery('SELECT * FROM users WHERE login_name = ?', login_name).first
        if duplicated
          db.query('ROLLBACK')
          halt_with_error 409, 'duplicated'
        end

        db.xquery('INSERT INTO users (login_name, pass_hash, nickname) VALUES (?, SHA2(?, 256), ?)', login_name, password, nickname)
        user_id = db.last_id
        db.query('COMMIT')
      rescue => e
        warn "rollback by: #{e}"
        db.query('ROLLBACK')
        halt_with_error
      end

      status 201
      { id: user_id, nickname: nickname }.to_json
    end

    get '/api/users/:id', login_required: false do |user_id|
      user = db.xquery('SELECT id, nickname FROM users WHERE id = ?', user_id).first
      #if user['id'] != get_login_user['id']
       # halt_with_error 403, 'forbidden'
      #end
      
      rows = db.xquery('SELECT r.* FROM reservations r WHERE r.user_id = ? ORDER BY last_updated_at DESC LIMIT 5', user['id'])
      event_ids = rows.map { |r| r['event_id'] }
      unless event_ids.empty?
      	target_events = db.query("SELECT * FROM events WHERE id IN (#{event_ids.join(',')})").to_a
      	#return target_events.to_json
        #return get_event_detail(target_events).to_json
        events = get_event_detail(target_events).map do |row|
          [row['id'], row]
      	end.to_h
      end
      recent_reservations = rows.map do |row|
        sheet = get_sheet(row['sheet_id'])
        event = events[row['event_id']]
        price = event['sheets'][sheet[:rank]]['price']
        event_dup = Marshal.load(Marshal.dump(event))
        event_dup.delete('sheets')
        event_dup.delete('total')
        event_dup.delete('remains')

        {
          id:          row['id'],
          event:       event_dup,
          sheet_rank:  sheet[:rank],
          sheet_num:   sheet[:num],
          price:       price,
          reserved_at: row['reserved_at'].to_i,
          canceled_at: row['canceled_at']&.to_i,
        }
      end

      user['recent_reservations'] = recent_reservations
      user_reser = db.xquery('SELECT r.*, e.price FROM reservations r INNER JOIN events e ON e.id = r.event_id WHERE r.user_id = ? AND not_canceled', user['id']).to_a
      # user['total_price'] = db.xquery('SELECT r.*, e.price as price FROM reservations r INNER JOIN events e ON e.id = r.event_id WHERE r.user_id = ? AND not_canceled', user['id']).to_a['total_price']
      total_price = 0
      user_reser.each do |r|
        total_price = total_price + r['price']
        sheet = get_sheet(r['sheet_id'])
        total_price = total_price + sheet[:price]
      end
      user['total_price'] = total_price

      rows = db.xquery('SELECT event_id FROM reservations WHERE user_id = ? GROUP BY event_id ORDER BY MAX(last_updated_at) DESC LIMIT 5', user['id'])
      event_ids = rows.map { |r| r['event_id'] }
      unless event_ids.empty?
      	target_events = db.query("SELECT * FROM events WHERE id IN (#{event_ids.join(',')})").to_a
      	#return target_events.to_json
        #return get_event_detail(target_events).to_json
        events = get_event_detail(target_events).map do |row|
          [row['id'], row]
      	end.to_h
      end
      recent_events = rows.map do |row|
        # event = get_event(row['event_id'])
        event = events[row['event_id']]
        event['sheets'].each { |_, sheet| sheet.delete('detail') }
        event
      end
      user['recent_events'] = recent_events

      user.to_json
    end


    post '/api/actions/login' do
      login_name = body_params['login_name']
      password   = body_params['password']

      user      = db.xquery('SELECT * FROM users WHERE login_name = ?', login_name).first
      pass_hash = db.xquery('SELECT SHA2(?, 256) AS pass_hash', password).first['pass_hash']
      halt_with_error 401, 'authentication_failed' if user.nil? || pass_hash != user['pass_hash']

      session['user_id'] = user['id']
      session['user'] = user

      user = get_login_user
      user.to_json
    end

    post '/api/actions/logout', login_required: true do
      session.delete('user_id')
      status 204
    end

    get '/api/events' do
      events = get_events.map(&method(:sanitize_event))
      events.to_json
    end

    get '/api/events/:id' do |event_id|
      user = get_login_user || {}
      target_events = db.query("SELECT * FROM events WHERE id = #{event_id} LIMIT 1").first
      halt_with_error 404, 'not_found' if target_events.nil?
      event = get_event_detail([target_events], user['id']).first
      halt_with_error 404, 'not_found' if event.nil? || !event['public']

      event = sanitize_event(event)
      event.to_json
    end

    post '/api/events/:id/actions/reserve', login_required: true do |event_id|
      rank = body_params['sheet_rank']

      user  = get_login_user
      event = db.query("SELECT * FROM events WHERE id = #{event_id} LIMIT 1").first
      halt_with_error 404, 'invalid_event' unless event && event['public_fg']
      halt_with_error 400, 'invalid_rank' unless validate_rank(rank)
      sheet = nil
      reservation_id = nil
      sheet_ids = db.xquery("SELECT sheet_id FROM reservations WHERE event_id = #{event['id']} AND not_canceled FOR UPDATE").map do |row|
        row['sheet_id']
      end
      #halt_with_error 409, 'sold_out' if sheet_ids.empty?
      where_in = sheet_ids.empty? ? "" : "NOT IN (#{sheet_ids.join(',')})"
      sheets = db.xquery("SELECT * FROM sheets WHERE id #{where_in} AND `rank` = ?", rank).to_a
      loop do
        sheet = sheets.sample
        halt_with_error 409, 'sold_out' unless sheet
        db.query('BEGIN')
        begin
          db.xquery('INSERT INTO reservations (event_id, sheet_id, user_id, reserved_at) VALUES (?, ?, ?, ?)', event['id'], sheet['id'], user['id'], Time.now.utc.strftime('%F %T.%6N'))
          reservation_id = db.last_id
          db.query('COMMIT')
        rescue => e
          db.query('ROLLBACK')
          warn "re-try: rollback by #{e}"
          next
        end

        break
      end

      status 202
      { id: reservation_id, sheet_rank: rank, sheet_num: sheet['num'] } .to_json
    end

    delete '/api/events/:id/sheets/:rank/:num/reservation', login_required: true do |event_id, rank, num|
      user  = get_login_user
      event = db.query("SELECT * FROM events WHERE id = #{event_id} LIMIT 1").first
      # halt_with_error 404, 'invalid_event' unless event
      # event = get_event_detail([event], user['id']).first
      halt_with_error 404, 'invalid_event' unless event && event['public_fg']
      halt_with_error 404, 'invalid_rank'  unless validate_rank(rank)

      sheet = db.xquery('SELECT * FROM sheets WHERE `rank` = ? AND num = ? LIMIT 1', rank, num).first
      halt_with_error 404, 'invalid_sheet' unless sheet

      db.query('BEGIN')
      begin
        # reservation = db.xquery('SELECT * FROM reservations WHERE event_id = ? AND sheet_id = ? AND not_canceled GROUP BY event_id HAVING reserved_at = MIN(reserved_at) FOR UPDATE', event['id'], sheet['id']).first
        reservation = db.xquery('SELECT * FROM reservations WHERE event_id = ? AND sheet_id = ? AND not_canceled ORDER BY reserved_at LIMIT 1 FOR UPDATE', event['id'], sheet['id']).first
        unless reservation
          db.query('ROLLBACK')
          halt_with_error 400, 'not_reserved'
        end
        if reservation['user_id'] != user['id']
          db.query('ROLLBACK')
          halt_with_error 403, 'not_permitted'
        end

        db.xquery('UPDATE reservations SET canceled_at = ? WHERE id = ?', Time.now.utc.strftime('%F %T.%6N'), reservation['id'])
        db.query('COMMIT')
      rescue => e
        warn "rollback by: #{e}"
        db.query('ROLLBACK')
        halt_with_error
      end

      status 204
    end

    get '/admin/' do
      @administrator = get_login_administrator
      @events = get_events(->(_) { true }) if @administrator

      erb :admin
    end

    post '/admin/api/actions/login' do
      login_name = body_params['login_name']
      password   = body_params['password']

      administrator = db.xquery('SELECT * FROM administrators WHERE login_name = ?', login_name).first
      pass_hash     = db.xquery('SELECT SHA2(?, 256) AS pass_hash', password).first['pass_hash']
      halt_with_error 401, 'authentication_failed' if administrator.nil? || pass_hash != administrator['pass_hash']

      session['administrator_id'] = administrator['id']
      session['admin'] = administrator

      administrator = get_login_administrator
      administrator.to_json
    end

    post '/admin/api/actions/logout', admin_login_required: true do
      session.delete('administrator_id')
      status 204
    end

    get '/admin/api/events', admin_login_required: true do
      events = get_events(->(_) { true })
      events.to_json
    end

    post '/admin/api/events', admin_login_required: true do
      title  = body_params['title']
      public = body_params['public'] || false
      price  = body_params['price']

      db.query('BEGIN')
      begin
        db.xquery('INSERT INTO events (title, public_fg, closed_fg, price) VALUES (?, ?, 0, ?)', title, public, price)
        event_id = db.last_id
        db.query('COMMIT')
      rescue
        db.query('ROLLBACK')
      end
      event = db.query("SELECT * FROM events WHERE id = #{event_id} LIMIT 1").first
      # halt_with_error 404, 'not_found' if event.nil?
      event = get_event_detail([event]).first
      event&.to_json
    end

    get '/admin/api/events/:id', admin_login_required: true do |event_id|
      event = db.query("SELECT * FROM events WHERE id = #{event_id} LIMIT 1").first
      halt_with_error 404, 'not_found' if event.nil?
      event = get_event_detail([event]).first
      halt_with_error 404, 'not_found' unless event

      event.to_json
    end

    post '/admin/api/events/:id/actions/edit', admin_login_required: true do |event_id|
      public = body_params['public'] || false
      closed = body_params['closed'] || false
      public = false if closed
      event = db.query("SELECT * FROM events WHERE id = #{event_id} LIMIT 1").first
      # event = get_event(event_id)
      halt_with_error 404, 'not_found' unless event

      if event['closed_fg']
        halt_with_error 400, 'cannot_edit_closed_event'
      elsif event['public_fg'] && closed
        halt_with_error 400, 'cannot_close_public_event'
      end

      db.query('BEGIN')
      begin
        db.xquery('UPDATE events SET public_fg = ?, closed_fg = ? WHERE id = ?', public, closed, event['id'])
        db.query('COMMIT')
      rescue
        db.query('ROLLBACK')
      end
      event = db.query("SELECT * FROM events WHERE id = #{event_id} LIMIT 1").first
      event = get_event_detail([event]).first
      # event = get_event(event_id)
      event.to_json
    end

    get '/admin/api/reports/events/:id/sales', admin_login_required: true do |event_id|
      event = db.query("SELECT * FROM events WHERE id = #{event_id} LIMIT 1").first
      halt_with_error 404, 'not_found' if event.nil?
      event = get_event_detail([event]).first

      reservations = db.xquery('SELECT r.*, e.price AS event_price FROM reservations r INNER JOIN events e ON e.id = r.event_id WHERE r.event_id = ? ORDER BY reserved_at ASC FOR UPDATE', event['id'])
      reports = reservations.map do |reservation|
        sheet = get_sheet(reservation['sheet_id'])
        {
          reservation_id: reservation['id'],
          event_id:       event['id'],
          rank:           sheet[:rank],
          num:            sheet[:num],
          user_id:        reservation['user_id'],
          sold_at:        reservation['reserved_at'].iso8601,
          canceled_at:    reservation['canceled_at']&.iso8601 || '',
          price:          reservation['event_price'] + sheet[:price],
        }
      end

      render_report_csv(reports)
    end

    get '/admin/api/reports/sales', admin_login_required: true do
      reservations = db.query('SELECT r.*, e.id AS event_id, e.price AS event_price FROM reservations r INNER JOIN events e ON e.id = r.event_id ORDER BY reserved_at ASC FOR UPDATE')
      reports = reservations.map do |reservation|
        sheet = get_sheet(reservation['sheet_id'])
        {
          reservation_id: reservation['id'],
          event_id:       reservation['event_id'],
          rank:           sheet[:rank],
          num:            sheet[:num],
          user_id:        reservation['user_id'],
          sold_at:        reservation['reserved_at'].iso8601,
          canceled_at:    reservation['canceled_at']&.iso8601 || '',
          price:          reservation['event_price'] + sheet[:price],
        }
      end

      render_report_csv(reports)
    end
  end
end
