require 'net/http'
require 'uri'
require 'rexml/document'

include REXML

class SolrStatistics < Scout::Plugin
    needs 'json'

    OPTIONS=<<-EOS
        location:
            name: Stats URL
            default: "http://localhost:8983/solr/admin/stats.jsp"
        handlers:
            name: Handlers to monitor (comma separated)
            default: "standard,/update"
    EOS

    def build_report
        location = option(:location) || 'http://localhost:8983/solr/admin/stats.jsp'
        handlers = (option(:handlers) || 'standard,/update').split(',')
        get_stats(location, handlers)
    end

    def get_stats(location, handlers)
        url = URI.parse(location)
        res = Net::HTTP.start(url.host, url.port) {|http|
            http.get(url.path)
        }
        xmldoc = Document.new(res.body)
        
        # Find the number of documents
        node = XPath.first(xmldoc, "//solr/solr-info/CORE/entry[contains(name, 'searcher')]")
        num_docs = Integer(XPath.first(node, "*//stat[@name='numDocs']").text.strip)

        report(:numDocs => num_docs)

        handlers.each {|handler|
            get_handler_stats(xmldoc, handler)
        }
    end

    def get_handler_stats(xmldoc, handler)
        node = XPath.first(xmldoc, "//solr/solr-info/QUERYHANDLER/entry[contains(name, '#{handler}')]")
        if node
            requests = Integer(XPath.first(node, "*//stat[@name='requests']").text.strip)
            time = Integer(XPath.first(node, "*//stat[@name='totalTime']").text.strip)
            avg_time = XPath.first(node, "*//stat[@name='avgTimePerRequest']").text.strip

            counter(handler + '-requests', requests, :per => :second)
            counter(handler + '-time', time, :per => :second)
            report(
                handler + '-delta' => get_delta_rt(handler, requests, time),
                handler + '-avg' => avg_time
            )
        end
    end


    def get_delta_rt(handler, requests, time)
        key_values = handler + '::prev_values'

        prev_values = memory key_values
        remember key_values => sprintf('%s::%s', requests, time)

        if not prev_values
            return 
        end

        prev_requests, prev_time = prev_values.split('::')

        prev_requests = Integer(prev_requests)
        prev_time = Integer(prev_time)

        delta_requests = requests - prev_requests
        delta_time = time - prev_time

        # If no new requests were issued then we return the previous delta
        if delta_requests == 0 or delta_time == 0
            return 0
        end
        value = delta_time.to_f / delta_requests
        return value
    end
end
