set -e

cd /server
if ! mysql -e "SHOW DATABASES LIKE 'auth';"|grep auth ;then
  echo Creating database...
  mysql -uroot < /TC/sql/create/create_mysql.sql
  mysql -utrinity -ptrinity auth < /TC/sql/base/auth_database.sql
  mysql -utrinity -ptrinity characters < /TC/sql/base/characters_database.sql
  mysql -utrinity -ptrinity world < /server/bin/TDB.sql
;else
  echo Auth database exists!
;fi
 
bin/authserver -c etc/authserver.conf & bin/worldserver -c etc/worldserver.conf
