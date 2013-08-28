class PostgresqlMonitoring< Scout::Plugin
  # need the ruby-pg gem
  needs 'pg'
  
  OPTIONS=<<-EOS
    user:
      name: PostgreSQL username
      notes: Specify the username to connect with
      default: postgres
    password:
      name: PostgreSQL password
      notes: Specify the password to connect with
      attributes: password
    master:
      name: PostgreSQL master host
      notes: Specify the host name of the PostgreSQL master server. 
      default: 10.0.2.11
    slave:
      name: PostgreSQL slave host
      notes: Specify the host name of the PostgreSQL slave server.
  EOS

  def build_report
    report = {}

    master_hostname, master_port = option(:master)
    master_port = (master_port or 5432).to_i

    slave_hostname, slave_port = option(:slave)
    slave_port = (slave_port or 5432).to_i
    
    begin
      pg_conn_master = PGconn.new(
        :host=>master_hostname,
        :user=>option(:user), 
        :password=>option(:password), 
        :port=>master_port,
        :dbname=>option(:dbname))
    rescue PGError => e
      return errors << {
        :subject => "Unable to connect to PostgreSQL master server",
        :body => "Scout was unable to connect to the PostgreSQL master server: \n\n#{e}\n\n#{e.backtrace}"
      }
    end

    begin
      pg_conn_slave = PGconn.new(
        :host=>slave_hostname,
        :user=>option(:user), 
        :password=>option(:password), 
        :port=>slave_port,
        :dbname=>option(:dbname))
    rescue PGError => e
      return errors << {
        :subject => "Unable to connect to PostgreSQL slave server",
        :body => "Scout was unable to connect to the PostgreSQL slave server: \n\n#{e}\n\n#{e.backtrace}"
      }
    end

    # Get segment size in bytes
    segment_size = pg_conn_master.exec('SHOW wal_segment_size').getvalue(0, 0).sub(/\D+/, '').to_i << 20

    pos_master = pg_conn_master.exec('SELECT pg_current_xlog_location()').getvalue(0, 0)
    pos_slave = pg_conn_slave.exec('SELECT pg_last_xlog_receive_location()').getvalue(0, 0)
    replay_slave = pg_conn_slave.exec('SELECT pg_last_xlog_replay_location()').getvalue(0, 0)


    report['offset_receive'] = calculate_offset(pos_master, pos_slave, segment_size)
    report['offset_replay'] = calculate_offset(pos_slave, replay_slave, segment_size)

    report(report) if report.values.compact.any?

  end

  def calculate_offset(first, second, segment_size)
    segment, offset = first.split('/')
    pos_1 = (segment.to_i * segment_size) + offset.to_i(16)

    segment, offset = second.split('/')
    pos_2 = (segment.to_i * segment_size) + offset.to_i(16)
    return pos_2 - pos_1
  end
end
