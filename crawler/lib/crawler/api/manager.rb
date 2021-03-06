require "celluloid"
require_relative "logging"
require_relative "tokens"
module Crawler
  module Api
    class Manager

      include Logging
      include Celluloid

      # Cushion is additional time to delay between requests
      # It appears that it is actually not needed, moreover you can boost performance
      # by setting it negative

      # The results of the tests are
      # for 2 tokens
      #   {:average_request_time=>0.1667786095, :fail_rate=>0.0, :cushion=>0.0}
      #   {:average_request_time=>0.1534757537, :fail_rate=>0.0, :cushion=>-0.025}
      #   {:average_request_time=>0.15984273987, :fail_rate=>0.1, :cushion=>-0.05}
      # for 1 token
      #   {:time=>0.3371227969, :fail_rate=>0.0, :cushion=>0.0}
      #   {:time=>0.33942607017000004, :fail_rate=>0.1, :cushion=>-0.025}
      #   {:time=>0.3450395382, :fail_rate=>0.2, :cushion=>-0.05}
      # See rake cushion task for details

      # overall 0 value is pretty safe, while negative value give random boost or not

      attr_accessor :cushion
      finalizer :shutdown

      def initialize(args={})
        args=defaults.merge args
        @tokens=Tokens.new source: args[:token_filename]
        @server_requests_per_sec=args[:server_requests_per_sec]
        @id_requests_per_sec=args[:id_requests_per_sec]
        @queue=args[:queue]
        @requester=args[:requester]
        @cushion = args[:cushion] || 0
      end

      def start
        @active=true
        while @active
          begin
            tuple=@queue.pop(true)
          rescue ThreadError
            @active ? Actor.current.wait(:pushed) : next
            retry
          end
          begin
            token=@tokens.pick
          rescue Tokens::EmptyTokensFile
            response = {error: "Tokens file is empty", incoming: tuple[:incoming]}
            tuple[:socket].write response.to_json+"\r\n"
            next
          end
          tuple[:request] << "access_token=#{token[:value]}"
          tuple[:queue] = @queue
          wait_to_be_polite_to_server(token)
          log.info "Starting request #{tuple[:request]}"
          @requester.async.push tuple
          @tokens.touch(token)
        end
      end


      def shutdown
        @active=false
      end

      private

      def wait_to_be_polite_to_server(token)
        delay=token_sleep_time(token)
        sleep delay + @cushion if delay>0
      end

      def token_sleep_time(token)
        now=Time.now
        delay=[sleep_time(token[:last_used], now, @id_requests_per_sec), sleep_time(@tokens.last_used, now, @server_requests_per_sec)].max
        delay.round(3)
      end

      def sleep_time(last_used, now, frequency)
        [1.0/frequency-now.to_f+last_used.to_f, 0].max
      end

      def defaults
        {server_requests_per_sec: 5, id_requests_per_sec: 3, token_filename: 'tokens.csv'}
      end

    end
  end
end
