#!/usr/bin/env bash
set -e

DEFAULT_PASSWD=1234

Usage() {
  echo "Usage: generate-certificates.sh [options] "
  echo " -g, --generate - generate certificates "
  echo " -i, --import - describe how to import certificates "
  echo " -r, --remove - describe how to remove imported certificates "
  echo " -p, --password value - override default ($DEFAULT_PASSWD) password "
  echo " -h, --help - display this help and exit"
}

PASSWD=$DEFAULT_PASSWD

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -g|--generate)
      GENERATE=1
      shift
      ;;
    -i|--import)
      IMPORT=1
      shift
      ;;
    -r|--remove)
      REMOVE=1
      shift
      ;;
    -p|--password)
      PASSWD="$2"
      shift
      shift
      ;;
    -h|--help)
      shift
      Usage;
      exit 0
      ;;
    -*|--*)
      echo "$(basename $0) unrecognized option $1"
      Usage
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

if [[ $GENERATE -ne 1 && $IMPORT -ne 1 && $REMOVE -ne 1 ]]; then
  echo "either use an option to generate, to import or to remove a certificate"
  Usage
  exit 1
fi

if [[ -z "$PASSWD" ]]; then
  echo "password cannot be an empty string"
  Usage
  exit 1
fi

NAME=localhost
SUBJ="
C=US
ST=CA
L=San Francisco
O=Expo DEV
OU=Expo DEV
CN=$NAME
emailAddress=admin@$NAME
"

if [[ $GENERATE -eq 1 ]]; then
  openssl genrsa -des3 -out CA.key -passout pass:"$PASSWD" 2048
  openssl req -x509 -new -nodes -subj "$(echo -n "$SUBJ" | tr "\n" "/")" \
              -key CA.key -passin pass:"$PASSWD" -sha256 -days 825 -out CA.pem \
              -addext "subjectAltName = DNS:$NAME"
  
  openssl genrsa -out $NAME.key 2048
  openssl req -new -subj "$(echo -n "$SUBJ" | tr "\n" "/")" -key "$NAME.key" -out "$NAME.csr" \
              -addext "subjectAltName = DNS:$NAME"
  >$NAME.ext cat <<-EOF
  authorityKeyIdentifier=keyid,issuer
  basicConstraints=CA:FALSE
  keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
EOF
  
  openssl x509 -req -in $NAME.csr -CA CA.pem -CAkey CA.key -CAcreateserial \
               -out $NAME.crt -days 825 -sha256 -extfile $NAME.ext -passin pass:"$PASSWD"
      
  openssl pkcs12 -export -out CA.pfx -inkey CA.key -in CA.pem -passin pass:"$PASSWD" -passout pass:"$PASSWD" 
fi

if [[ $IMPORT -eq 1 ]]; then
  echo
  echo "# Note: browser restard is required"
  echo
  echo "# Fedora Linux:"
  if ! command -v certutil &> /dev/null
  then
      echo "sudo dnf install nss-tools"
  fi
  echo "sudo trust anchor --store CA.pem"
  echo "certutil -d \"$(echo -n $HOME/.mozilla/firefox/*.default-release)\" -A -t \"C,,\" -n $NAME -i CA.pem"
  echo "certutil -d \"$HOME/.pki/nssdb\" -A -t \"C,,\" -n $NAME -i CA.pem"
  echo
  echo "# Ubuntu Linux:"
  echo "certutil -d \"$(echo -n $HOME/.mozilla/firefox/*.default-release)\" -A -t \"C,,\" -n $NAME -i CA.pem"
  echo "certutil -d \"$HOME/.pki/nssdb\" -A -t \"C,,\" -n $NAME -i CA.pem"
  echo
  echo "# Windows (PowerShell):"
  echo "Import-Certificate -FilePath CA.pem -CertStoreLocation Cert:\CurrentUser\Root"
  echo
  echo "# Windows (Command Line):"
  echo "certutil.exe -user -addstore root CA.pem"
  echo
fi

if [[ $REMOVE -eq 1 ]]; then
  echo
  echo "# Note: browser restard is required"
  echo
  echo "# Fedora Linux:"
  if ! command -v certutil &> /dev/null
  then
      echo "sudo dnf install nss-tools"
  fi
  echo "sudo trust anchor --remove CA.pem"
  echo "certutil -d \"$(echo -n $HOME/.mozilla/firefox/*.default-release)\" -D -n $NAME"
  echo "certutil -d \"$HOME/.pki/nssdb\" -D -n $NAME"
  echo
  echo "# Ubuntu Linux:"
  echo "certutil -d \"$(echo -n $HOME/.mozilla/firefox/*.default-release)\" -D -n $NAME"
  echo "certutil -d \"$HOME/.pki/nssdb\" -D -n $NAME"
  echo
fi
