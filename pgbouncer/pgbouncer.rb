class PGBouncer < Scout::Plugin
    # need the ruby-pg gem
    needs 'pg'
  
    OPTIONS=<<-EOS
        user:
            name: PGBouncer username
            notes: Specify the username to connect with
        password:
            name: PGBouncer password
            notes: Specify the password to connect with
            attributes: password
        host:
            name: PGBouncer host
            notes: Specify the host name of the PGBouncer daemon. If the value begins with
                    a slash it is used as the directory for the Unix-domain socket. An empty
                    string uses the default Unix-domain socket.
            default: localhost
        dbname:
            name: Database
            notes: The database name to monitor
            default: postgres
        port:
            name: PGBouncer port
            notes: Specify the port to connect to PostgreSQL with
            default: 6432
    EOS

    def build_report
        now = Time.now
        report = {}
        
        begin
            pgconn = PGconn.new(
                    :host => option(:host), 
                    :user => option(:user), 
                    :password => option(:password), 
                    :port => option(:port).to_i, 
                    :dbname => 'pgbouncer')

        rescue PGError => e
            return errors << {
                :subject => "Unable to connect to PGBouncer.",
                :body => "Scout was unable to connect to the PostgreSQL server: \n\n#{e}\n\n#{e.backtrace}"
        }
        end
        result = pgconn.exec('SHOW stats');

        result.each do |row|
            puts row
            if row['database'] != option(:dbname)
                next
            end
            puts row
            report(
                :avg_req => row['avg_req'],
                :avg_recv => row['avg_recv'],
                :avg_sent => row['avg_sent'],
                :avg_query => row['avg_query'] / 1000
            )
        end
    end
end

