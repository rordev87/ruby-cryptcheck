PWD = $(shell pwd)
OPENSSL_LIB_VERSION = 1.0.0
OPENSSL_VERSION = 1.0.2j
OPENSSL_NAME = openssl-$(OPENSSL_VERSION)
OPENSSL_DIR = build/$(OPENSSL_NAME)
RUBY_MAJOR_VERSION = 2.3
RUBY_VERSION = $(RUBY_MAJOR_VERSION).8
RUBY_NAME = ruby-$(RUBY_VERSION)
RUBY_DIR = build/$(RUBY_NAME)
RUBY_OPENSSL_EXT_DIR = $(RUBY_DIR)/ext/openssl
RBENV_DIR = $(RBENV_ROOT)/versions/$(RUBY_VERSION)-cryptcheck
RUBY_LIB_DIR = $(RBENV_DIR)/lib/ruby/$(RUBY_MAJOR_VERSION).0
RBENV_ROOT ?= ~/.rbenv
export LIBRARY_PATH ?= $(PWD)/lib
export C_INCLUDE_PATH ?= $(PWD)/build/openssl/include
export LD_LIBRARY_PATH ?= $(PWD)/lib

.SECONDARY:
.SUFFIXES:

all: libs ext

clean: clean-libs clean-ext
clean-libs:
	[ -d "build/openssl/" ] \
		&& find "build/openssl/" \( -name "*.o" -o -name "*.so" \) -delete \
		|| true
	rm -f lib/libcrypto.so* lib/libssl.so* "build/openssl//Makefile"
clean-ext:
	[ -d "$(RUBY_OPENSSL_EXT_DIR)" ] \
		&& find "$(RUBY_OPENSSL_EXT_DIR)" \( -name "*.o" -o -name "*.so" \) -delete \
		|| true
	rm -f lib/openssl.so
mr-proper:
	rm -rf lib/libcrypto.so* lib/libssl.so* lib/openssl.so build

build/:
	mkdir "$@"

build/chacha-poly.patch: | build/
	wget https://github.com/cloudflare/sslconfig/raw/master/patches/openssl__chacha20_poly1305_draft_and_rfc_ossl102j.patch -O "$@"

build/$(OPENSSL_NAME).tar.gz: | build/
	wget "https://www.openssl.org/source/$(OPENSSL_NAME).tar.gz" -O "$@"

build/openssl/: | $(OPENSSL_DIR)/
	ln -s "$(OPENSSL_NAME)" "build/openssl"

$(OPENSSL_DIR)/: build/$(OPENSSL_NAME).tar.gz build/chacha-poly.patch
	tar -C build -xf "build/$(OPENSSL_NAME).tar.gz"
	patch -d "$(OPENSSL_DIR)" -p1 < build/chacha-poly.patch
	patch -d "$(OPENSSL_DIR)" -p1 < patches/openssl/00_disable_digest_check.patch

build/openssl/Makefile: | build/openssl/
	#cd $(OPENSSL_DIR) && ./Configure enable-ssl2 enable-ssl3 enable-weak-ssl-ciphers enable-zlib enable-rc5 enable-rc2 enable-gost enable-md2 enable-mdc2 enable-shared linux-x86_64
	#cd $(OPENSSL_DIR) && ./config enable-ssl2 enable-ssl3 enable-md2 enable-rc5 enable-weak-ssl-ciphers shared
	cd build/openssl/ && ./config enable-ssl2 enable-ssl3 enable-ssl3-method enable-md2 enable-rc5 enable-weak-ssl-ciphers enable-shared

build/openssl/libssl.so \
build/openssl/libcrypto.so: build/openssl/Makefile
	$(MAKE) -C build/openssl/

install-openssl: build/openssl/Makefile
	$(MAKE) -C build/openssl/ install

LIBS = lib/libssl.so lib/libcrypto.so lib/libssl.so.$(OPENSSL_LIB_VERSION) lib/libcrypto.so.$(OPENSSL_LIB_VERSION)
lib/%.so: build/openssl/%.so
	cp "$<" "$@"
lib/%.so.$(OPENSSL_LIB_VERSION): lib/%.so
	ln -fs "$(notdir $(subst .$(OPENSSL_LIB_VERSION),,$@))" "$@"
libs: $(LIBS)

$(RBENV_ROOT)/:
	git clone https://github.com/rbenv/rbenv/ $@ -b v1.1.1 --depth 1

$(RBENV_ROOT)/plugins/ruby-build/: | $(RBENV_ROOT)/
	git clone https://github.com/rbenv/ruby-build/ $@ -b v20171215 --depth 1

$(RBENV_ROOT)/plugins/ruby-build/share/ruby-build/$(RUBY_VERSION): | $(RBENV_ROOT)/plugins/ruby-build/

build/$(RUBY_VERSION)-cryptcheck: $(RBENV_ROOT)/plugins/ruby-build/share/ruby-build/$(RUBY_VERSION)
	cp "$<" "$@"

install-rbenv: build/$(RUBY_VERSION)-cryptcheck

install-rbenv-cryptcheck: build/$(RUBY_VERSION)-cryptcheck $(LIBS) | build/openssl/
	cat patches/ruby/*.patch | \
	RUBY_BUILD_CACHE_PATH="$(PWD)/build" \
	RUBY_BUILD_DEFINITIONS="$(PWD)/build" \
	rbenv install -fp "$(RUBY_VERSION)-cryptcheck"
	rbenv local "$(RUBY_VERSION)-cryptcheck"
	gem update --system
	gem install bundler
	# bundle install --without test development

$(RUBY_LIB_DIR)/openssl/ssl.rb: $(RUBY_OPENSSL_EXT_DIR)/lib/openssl/ssl.rb
	cp "$<" "$@"

$(RUBY_LIB_DIR)/x86_64-linux/openssl.so: $(RUBY_OPENSSL_EXT_DIR)/openssl.so
	cp "$<" "$@"

sync-ruby: $(RUBY_LIB_DIR)/openssl/ssl.rb $(RUBY_LIB_DIR)/x86_64-linux/openssl.so

build/$(RUBY_NAME).tar.xz: | build/
	wget "http://cache.ruby-lang.org/pub/ruby/$(RUBY_MAJOR_VERSION)/$(RUBY_NAME).tar.xz" -O "$@"

$(RUBY_DIR)/: build/$(RUBY_NAME).tar.xz
	tar -C build -xf "$<"
	for p in patches/ruby/*.patch; do patch -d "$@" -p1 < $i; done

$(RUBY_OPENSSL_EXT_DIR)/Makefile: libs | $(RUBY_DIR)/
	cd "$(RUBY_OPENSSL_EXT_DIR)" && ruby extconf.rb

$(RUBY_OPENSSL_EXT_DIR)/openssl.so: $(LIBS) $(RUBY_OPENSSL_EXT_DIR)/Makefile
	top_srcdir=../.. $(MAKE) -C "$(RUBY_OPENSSL_EXT_DIR)"

lib/openssl.so: $(RUBY_OPENSSL_EXT_DIR)/openssl.so
	cp "$<" "$@"

ext: lib/openssl.so

install-ruby: $(RUBY_DIR)/
	cd "$(RUBY_DIR)/" && ./configure --enable-shared --disable-install-rdoc && make install

spec/faketime/libfaketime.so: spec/faketime/faketime.c spec/faketime/faketime.h
	$(CC) "$^" -o "$@" -shared -fPIC -ldl -std=c99 -Werror -Wall
lib/libfaketime.so: spec/faketime/libfaketime.so
	ln -fs "../$<" "$@"
faketime: lib/libfaketime.so

test-material:
	bin/generate-test-material.rb

test: spec/faketime/libfaketime.so
	bin/rspec
