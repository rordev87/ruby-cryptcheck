require 'erb'
require 'parallel'

module CryptCheck
	module Tls
		module Xmpp
			def self.analyze(host, port=nil, domain: nil, type: :s2s)
				domain ||= host
				::CryptCheck.analyze host, port do |family, ip, host|
					s = Server.new family, ip, port, hostname: host, type: type, domain: domain
					g = Grade.new s
					Logger.info { '' }
					g.display
					g
				end
			end

			def self.analyze_domain(domain, type: :s2s)
				service, port = case type
									when :s2s
										['_xmpp-server', 5269]
									when :c2s
										['_xmpp-client', 5222]
								end
				srv = Resolv::DNS.new.getresources("#{service}._tcp.#{domain}", Resolv::DNS::Resource::IN::SRV)
							  .sort_by(&:priority).first
				if srv
					hostname, port = srv.target.to_s, srv.port
				else # DNS is not correctly set, guess config…
					hostname = domain
				end
				self.analyze hostname, port, domain: domain, type: type
			end

			def self.analyze_file(input, output)
				::CryptCheck.analyze_file(input, 'output/xmpp.erb', output) { |host| self.analyze_domain host }
			end
		end
	end
end
