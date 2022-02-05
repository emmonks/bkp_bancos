#!/bin/bash
# Desenvolvido por: Eduardo Maronas Monks
# Script para criacao de dumps dos 
# bancos MySQL e Postgres
# MySQL:
# Devera ser criado um usuario dumper ou
# similar com permissoes em todas as bases
# Exemplo: GRANT ALL PRIVILEGES ON *.* TO dumper@localhost IDENTIFIED BY 'senac2010' WITH GRANT OPTION;
# Postgres:
# Dever ser permitido o localhost como trust
# no arquivo pg_hba.conf
# Armazenamento remoto:
# Devera ser permitido ao usuario root local acessar por
# SSH, com certificado no host remoto, com o usuario onde
# sera o armazenamento dos dumps 

# -- Variaveis de Ambiente ---

DATA=$(date +%Y-%m-%d_%H-%M)

# Diretorio local de backup
PBACKUP="/backup"

# Diretorio remoto de backup
RBACKUP="/backup/dumps"

# Usuario e host de destino
SDESTINO="dumper@IP_remoto"

HOST=$(hostname)

# Envio de e-mail com a confirmacao do backup
EMAIL="gerencia@minhaempresa.com.br"


# Usuario dumper e a senha do MySQL
#MYSQL --

MUSER="dumper"

MSENHA="senhadousuariodumperlocal"


# -- LIMPEZA ---
# Os arquivos dos ultimos 5 dias serao mantidos
NDIAS="5"

if [ ! -d ${PBACKUP} ]; then
	
	echo ""
	echo " A pasta de backup nao foi encontrada!"
	mkdir -p ${PBACKUP}
	echo " Iniciando Tarefa de backup..."
	echo ""

else

	echo ""
	echo " Rotacionando backups mais antigos que $NDIAS"
	echo ""

	find ${PBACKUP} -type d -mtime +$NDIAS -exec rm -rf {} \;

fi

# Comentar algum procedimento na cron
# Exemplo para uma linha que contenha "php"
# Adiciona um "#" no comeco da linha
#sed -i '/php/s/^/#/g' /etc/crontab

# -- SCRIPT ---


echo "Iniciando o backup" |mutt -s "Backup $HOST Iniciado" $EMAIL


if [ ! -d $PBACKUP/$DATA/mysql ]; then

        mkdir -p $PBACKUP/$DATA/mysql

fi


for basemysql in `/usr/bin/mysql -u $MUSER -p$MSENHA --execute="show databases;" |grep -v "+" |grep -v Database`; do


        /usr/bin/mysqldump -u $MUSER --password=$MSENHA --databases $basemysql > $PBACKUP/$DATA/mysql/$basemysql.txt

        cd $PBACKUP/$DATA/mysql/

        tar -czvf $basemysql.tar.gz $basemysql.txt
		 
		sha1sum $basemysql.tar.gz > $basemysql.sha1

        rm -rf $basemysql.txt

	cd /

done

DAYOFWEEK=$(date +"%u")
if [ "${DAYOFWEEK}" -eq 7  ];  then

  # Todas as bases
  /usr/bin/mysqldump -p -u ${MUSER} --password=${MSENHA} --all-databases  > ${PBACKUP}/${DATA}/mysql/mysql_tudo.txt

   cd ${PBACKUP}/${DATA}/mysql/

   tar -czvf mysql_tudo.tar.gz mysql_tudo.txt
   
   sha1sum mysql_tudo.tar.gz > mysql_tudo.sha1

   rm -f mysql_tudo.txt
    
  
fi


cd /

# Usuarios
/usr/bin/mysqldump -u $MUSER --password=$MSENHA --no-create-info  mysql user > $PBACKUP/$DATA/mysql/usuarios.sql


# Grants
/usr/bin/mysql -u $MUSER --password=$MSENHA --skip-column-names -A -e"SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user<>''" | mysql -u $MUSER --password=$MSENHA --skip-column-names -A | sed 's/$/;/g' > $PBACKUP/$DATA/mysql/grants.sql

### Postgres

if [ ! -d $PBACKUP/$DATA/postgres ]; then

        mkdir -p $PBACKUP/$DATA/postgres

fi

chown -R postgres:postgres $PBACKUP/$DATA/postgres/


su - postgres -c "vacuumdb -a -f -z"

for basepostgres in $(su - postgres -c "psql -l" | grep -v template0|grep -v template1|grep "|" |grep -v Owner |awk '{if ($1 != "|" && $1 != "Nome") print $1}'); do

        su - postgres -c "pg_dump $basepostgres > $PBACKUP/$DATA/postgres/$basepostgres.txt"

        cd $PBACKUP/$DATA/postgres/

        tar -czvf $basepostgres.tar.gz $basepostgres.txt
		
		sha1sum $basepostgres.tar.gz > $basepostgres.sha1

        rm -rf $basepostgres.txt

	cd /

done


# Backup de usuarios do Postgresql

su - postgres -c "pg_dumpall --globals-only -S postgres > $PBACKUP/$DATA/postgres/usuarios.sql"
#su - postgres -c "pg_dumpall -U postgres --roles-only -f $PBACKUP/$DATA/postgres/roles.sql"

DAYOFWEEK=$(date +"%u")
if [ "${DAYOFWEEK}" -eq 7  ];  then

  # Otimizacao das tabelas
  su - postgres -c "vacuumdb -a -f -z"
  
  # Backup de todo o banco
  su - postgres -c "pg_dumpall > $PBACKUP/$DATA/postgres/postgres_tudo.txt"
  
  cd ${PBACKUP}/${DATA}/postgres/

  tar -czvf postgres_tudo.tar.gz postgres_tudo.txt
   
  sha1sum postgres_tudo.tar.gz > postgres_tudo.sha1

  rm -f postgres_tudo.txt  

fi


# Verifica se existe um diretorio com o nome do host no host remoto
if [ $(ssh  $SDESTINO "ls ${RBACKUP}" |grep -i $HOST |wc -l) = 0 ]; then

        ssh  $SDESTINO "mkdir -p ${RBACKUP}/$HOST"

fi

# Descomenta na cron alguma linha que foi comentada para a realizacao do backup
# Exemplo para uma linha que contenha "php"
# Remove um "#" no comeco da linha
#sed -i '/php/s/^#//g' /etc/crontab


# Copiar para o host de destino os dumps gerados localmente
scp -o StrictHostKeyChecking=no -r $PBACKUP/$DATA $SDESTINO:${RBACKUP}/$HOST/

echo "Backup finalizado" |mutt -s "Backup $HOST Finalizado!" $EMAIL

# Realiza otimizacao das tabelas aos domingos

DAYOFWEEK=$(date +"%u")
if [ "${DAYOFWEEK}" -eq 7  ];  then

 # Otimizacao das tabelas 
   #/usr/bin/mysqlcheck -A -o -u root --password=SenhaRoot

fi

exit 0
