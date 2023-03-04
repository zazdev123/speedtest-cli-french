#!/bin/bash

unknown_os ()
{
  echo "L'OS détecté n'est pas reconnu dans ma base de données."
  echo
  echo "Le script continuera tout de même l'installation, mais il risque d'y avoir des problèmes de compatibiltié."
  echo "Vous pouvez néanmoins trouver le lien des OS et distributions Linux compatibles sur ce lien : https://packagecloud.io/docs#os_distro_version"
  echo
  echo "Le script original et les serveurs sont fournis par packagecloud.io ."
}

gpg_check ()
{
  echo "Détection de PGP..."
  if command -v gpg > /dev/null; then
    echo "PGP détecté..."
  else
    echo "Installation de gnupg pour la vérification PGP..."
    apt-get install -y gnupg
    if [ "$?" -ne "0" ]; then
      echo "Nous avons détecté un problème lors de l'installation, il est donc impossible de poursuivre."
      echo "Installation annulée."
      exit 1
    fi
  fi
}

curl_check ()
{
  echo "Détection de curl..."
  if command -v curl > /dev/null; then
    echo "curl détecté..."
  else
    echo "Installation de curl..."
    apt-get install -q -y curl
    if [ "$?" -ne "0" ]; then
      echo "Nous avons détecté un problème lors de l'installation, il est donc impossible de poursuivre."
      echo "Installation annulée."
      exit 1
    fi
  fi
}

install_debian_keyring ()
{
  if [ "${os,,}" = "debian" ]; then
    echo "Installation de debian-archive-keyring... "
    echo "apt-transport-https est disponible sur beaucoup de distributions Linux."
    apt-get install -y debian-archive-keyring &> /dev/null
  fi
}


detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    # some systems dont have lsb-release yet have the lsb_release binary and
    # vice-versa
    if [ -e /etc/lsb-release ]; then
      . /etc/lsb-release

      if [ "${ID}" = "raspbian" ]; then
        os=${ID}
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      else
        os=${DISTRIB_ID}
        dist=${DISTRIB_CODENAME}

        if [ -z "$dist" ]; then
          dist=${DISTRIB_RELEASE}
        fi
      fi

    elif [ `which lsb_release 2>/dev/null` ]; then
      dist=`lsb_release -c | cut -f2`
      os=`lsb_release -i | cut -f2 | awk '{ print tolower($1) }'`

    elif [ -e /etc/debian_version ]; then
      # some Debians have jessie/sid in their /etc/debian_version
      # while others have '6.0.7'
      os=`cat /etc/issue | head -1 | awk '{ print tolower($1) }'`
      if grep -q '/' /etc/debian_version; then
        dist=`cut --delimiter='/' -f1 /etc/debian_version`
      else
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      fi

    else
      unknown_os
    fi
  fi

  if [ -z "$dist" ]; then
    unknown_os
  fi

  # remove whitespace from OS and dist name
  os="${os// /}"
  dist="${dist// /}"

  echo "OS/Distribution détecté : $os/$dist."
}

detect_apt_version ()
{
  apt_version_full=`apt-get -v | head -1 | awk '{ print $2 }'`
  apt_version_major=`echo $apt_version_full | cut -d. -f1`
  apt_version_minor=`echo $apt_version_full | cut -d. -f2`
  apt_version_modified="${apt_version_major}${apt_version_minor}0"

  echo "Version d'APT détecté : ${apt_version_full}"
}

main ()
{
  detect_os
  curl_check
  gpg_check
  detect_apt_version

  # Need to first run apt-get update so that apt-transport-https can be
  # installed
  echo -n "Lancement de apt-get update... "
  apt-get update &> /dev/null
  echo "Effectué."

  # Install the debian-archive-keyring package on debian systems so that
  # apt-transport-https can be installed next
  install_debian_keyring

  echo -n "Installation de apt-transport-https... "
  apt-get install -y apt-transport-https &> /dev/null
  echo "Effectué."


  gpg_key_url="https://packagecloud.io/ookla/speedtest-cli/gpgkey"
  apt_config_url="https://packagecloud.io/install/repositories/ookla/speedtest-cli/config_file.list?os=${os}&dist=${dist}&source=script"

  apt_source_path="/etc/apt/sources.list.d/ookla_speedtest-cli.list"
  apt_keyrings_dir="/etc/apt/keyrings"
  if [ ! -d "$apt_keyrings_dir" ]; then
    mkdir -p "$apt_keyrings_dir"
  fi
  gpg_keyring_path="$apt_keyrings_dir/ookla_speedtest-cli-archive-keyring.gpg"
  gpg_key_path_old="/etc/apt/trusted.gpg.d/ookla_speedtest-cli.gpg"

  echo -n "Installation de $apt_source_path..."

  # create an apt config file for this repository
  curl -sSf "${apt_config_url}" > $apt_source_path
  curl_exit_code=$?

  if [ "$curl_exit_code" = "22" ]; then
    echo
    echo
    echo -n "Impossible de télécharger le repo à l'URL : "
    echo "${apt_config_url}"
    echo
    echo "Cela peut arriver lorsque votre OS/Distribution n'est  "
    echo "pas compatible avec ce script, comme dit plus en haut."
    echo
    [ -e $apt_source_path ] && rm $apt_source_path
    exit 1
  elif [ "$curl_exit_code" = "35" -o "$curl_exit_code" = "60" ]; then
    echo "Impossible d'executer: "
    echo "    curl ${apt_config_url}"
    echo "Il se peut que ça peut arriver à cause de :"
    echo
    echo " 1.) Certification invalide"
    echo " 2.) Une version de libssl trop ancienne"
    [ -e $apt_source_path ] && rm $apt_source_path
    exit 1
  elif [ "$curl_exit_code" -gt "0" ]; then
    echo
    echo "Impossible d'executer: "
    echo "    curl ${apt_config_url}"
    echo
    echo "Double check et réessayer"
    [ -e $apt_source_path ] && rm $apt_source_path
    exit 1
  else
    echo "Effectué."
  fi

  echo -n "Importation de la clé PGP de packagecloud..."
  # import the gpg key
  curl -fsSL "${gpg_key_url}" | gpg --dearmor > ${gpg_keyring_path}
  # grant 644 permisions to gpg keyring path
  chmod 0644 "${gpg_keyring_path}"

  # move gpg key to old path if apt version is older than 1.1
  if [ "${apt_version_modified}" -lt 110 ]; then
    # move to trusted.gpg.d
    mv ${gpg_keyring_path} ${gpg_key_path_old}
    # grant 644 permisions to gpg key path
    chmod 0644 "${gpg_key_path_old}"

    # deletes the keyrings directory if it is empty
    if ! ls -1qA $apt_keyrings_dir | grep -q .;then
      rm -r $apt_keyrings_dir
    fi
    echo "Clé PGP importé vers ${gpg_key_path_old}"
  else
    echo "Clé PGP importé vers ${gpg_keyring_path}"
  fi
  echo "Effectué."

  echo -n "Lancement de apt-get update... "
  # update apt on this system
  apt-get update &> /dev/null
  echo "Effectué."

  echo
  echo "Le repo est désormais installé sur ton serveur. Installation de speedtest..."
  sudo apt-get install speedtest
  
  #apt-get end
  echo "Speedtest installé. Pour lancer speedtest, fais la commande  speedtest  . Pour chosisir un serveur spécifique aux alentours, fais  speedtest --servers  , puis  speedtest -s<ID>  ."
  echo "En attendant, je te le lance."
  speedtest
}

main
