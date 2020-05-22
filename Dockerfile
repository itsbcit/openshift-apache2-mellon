FROM httpd:2.4-alpine AS builder

WORKDIR /tmp

RUN apk add --no-cache \
        autoconf \
        automake \
        curl-dev \
        g++ \
        glib-dev \
        libtool \
        libxml2-dev \
        libxslt-dev \
        make \
        perl-dev \
        py3-six \
        python \
        zlib-dev

RUN wget https://www.aleksey.com/xmlsec/download/xmlsec1-1.2.29.tar.gz \
 && tar zxf xmlsec1-1.2.29.tar.gz \
 && cd xmlsec1-1.2.29 \
 && ./configure \
        --enable-soap \
 && make \
 && make install

RUN wget https://dev.entrouvert.org/releases/lasso/lasso-2.5.1.tar.gz \
 && tar zxf lasso-2.5.1.tar.gz \
 && cd lasso-2.5.1 \
 && ./configure \
        --with-python=/usr/bin/python3.8 \
 && make \
 && make install

RUN wget https://github.com/latchset/mod_auth_mellon/releases/download/v0_16_0/mod_auth_mellon-0.16.0.tar.gz \
 && tar zxf mod_auth_mellon-0.16.0.tar.gz \
 && cd mod_auth_mellon-0.16.0 \
 && aclocal \
 && autoheader \
 && autoconf \
 && ./configure \
        --with-apxs2=/usr/local/apache2/bin/apxs \
 && make \
 && make install

FROM httpd:2.4-alpine

WORKDIR /

RUN apk add --no-cache \
        apr \
        glib \
        curl \
        libxslt \
        libltdl \
        rsync

COPY --from=builder /usr/local/apache2/modules/mod_auth_mellon.so /usr/local/apache2/modules/mod_auth_mellon.so
COPY --from=builder /usr/local/lib/liblasso* /usr/local/lib/
COPY --from=builder /usr/local/lib/libxmlsec1* /usr/local/lib/
COPY application.conf /usr/local/apache2/conf/application.conf

LABEL maintainer="jesse@weisner.ca, chriswood.ca@gmail.com"
LABEL xmlsec_version="1.2.29"
LABEL lasso_version="2.5.1"
LABEL mod_auth_mellon_version="0.16.0"
LABEL build_id="1590189573"

# Add docker-entrypoint script base
ADD https://github.com/itsbcit/docker-entrypoint/releases/download/v1.5/docker-entrypoint.tar.gz /docker-entrypoint.tar.gz
RUN tar zxvf docker-entrypoint.tar.gz && rm -f docker-entrypoint.tar.gz \
 && chmod -R 555 /docker-entrypoint.* \
 && chmod 664 /etc/passwd /etc/group /etc/shadow \
 && chown 0:0 /etc/shadow \
 && chmod 775 /etc

# Add dockerize
ADD https://github.com/jwilder/dockerize/releases/download/v0.6.0/dockerize-alpine-linux-amd64-v0.6.0.tar.gz /dockerize.tar.gz
RUN [ -d /usr/local/bin ] || mkdir -p /usr/local/bin \
 && tar zxf /dockerize.tar.gz -C /usr/local/bin \
 && chown 0:0 /usr/local/bin/dockerize \
 && chmod 0555 /usr/local/bin/dockerize \
 && rm -f /dockerize.tar.gz

ENV DOCKERIZE_ENV production

# Add Tini
ADD https://github.com/krallin/tini/releases/download/v0.18.0/tini-static-amd64 /tini
RUN chmod +x /tini

COPY 50-copy-config.sh /docker-entrypoint.d/


RUN perl -pi -e 's/^Listen 80$/Listen 8080/' /usr/local/apache2/conf/httpd.conf \
 && echo 'Include /usr/local/apache2/conf/application.conf' >> /usr/local/apache2/conf/httpd.conf \
 && /usr/local/apache2/bin/apxs -e -a -n ldap /usr/local/apache2/modules/mod_ldap.so \
 && /usr/local/apache2/bin/apxs -e -a -n auth_mellon /usr/local/apache2/modules/mod_auth_mellon.so \
 && mkdir /application \
 && chown root:root \
        /application \
        /usr/local/apache2/logs \
 && chmod 775 /application \
 && chown -R root:root /usr/local/apache2 \
 && find /usr/local/apache2/conf -type d -exec chmod 0775 {} \; \
 && find /usr/local/apache2/conf -type f -exec chmod 0664 {} \;

VOLUME /application
WORKDIR /application

EXPOSE 8080

ENTRYPOINT ["/tini", "--", "/docker-entrypoint.sh"]
CMD ["httpd-foreground"]
