module CryptCheck
	module Tls
		class Server < CryptCheck::TcpServer
			Method.each do |method|
				class_eval <<-RUBY_EVAL, __FILE__, __LINE__ + 1
					def #{method.to_sym.downcase}?
						@supported_methods.detect { |m| m == :#{method.to_sym} }
					end
				RUBY_EVAL
			end

			Cipher::TYPES.each do |type, _|
				class_eval <<-RUBY_EVAL, __FILE__, __LINE__ + 1
					def #{type}?
						uniq_supported_ciphers.any? { |c| c.#{type}? }
					end
				RUBY_EVAL
			end

			def ssl?
				sslv2? or sslv3?
			end

			def tls?
				tlsv1? or tlsv1_1? or tlsv1_2?
			end

			def tls_only?
				tls? and !ssl?
			end

			def tlsv1_2_only?
				tlsv1_2? and not ssl? and not tlsv1? and not tlsv1_1?
			end

			def pfs_only?
				uniq_supported_ciphers.all? { |c| c.pfs? }
			end

			def ecdhe_only?
				uniq_supported_ciphers.all? { |c| c.ecdhe? }
			end

			def aead_only?
				uniq_supported_ciphers.all? { |c| c.aead? }
			end

			def fallback_scsv?
				@fallback_scsv
			end

			def must_staple?
				@cert.extensions.any? { |e| e.oid == '1.3.6.1.5.5.7.1.24' }
			end

			def valid?
				@valid
			end

			def trusted?
				@trusted
			end

			def to_h
				ciphers_preference = @preferences.collect do |p, cs|
					case cs
					when :client
						{ protocol: p, client: true }
					when nil
						{ protocol: p, na: true }
					else
						{ protocol: p, cipher_suite: cs.collect(&:to_h) }
					end
				end

				curves_preferences = case @curves_preference
									 when :client
										 :client
									 else
										 @curves_preference&.collect(&:name)
									 end
				{
						certs:              @certs.collect(&:to_h),
						dh:                 @dh.collect(&:to_h),
						protocols:          @supported_methods.collect(&:to_h),
						ciphers:            uniq_supported_ciphers.collect(&:to_h),
						ciphers_preference: ciphers_preference,
						curves:             @supported_curves.collect(&:to_h),
						curves_preference:  curves_preferences,
						fallback_scsv:      @fallback_scsv
				}
			end

			protected
			include State

			CHECKS = [
					[:fallback_scsv, :good, -> (s) { s.fallback_scsv? }],
			# [:tlsv1_2_only, -> (s) { s.tlsv1_2_only? }, :great],
			# [:pfs_only, -> (s) { s.pfs_only? }, :great],
			# [:ecdhe_only, -> (s) { s.ecdhe_only? }, :great],
			# [:aead_only, -> (s) { s.aead_only? }, :best],
			].freeze

			def available_checks
				CHECKS
			end

			def children
				@certs + @dh + @supported_methods + uniq_supported_ciphers
			end

			include Engine
			include Grade
		end
	end
end
