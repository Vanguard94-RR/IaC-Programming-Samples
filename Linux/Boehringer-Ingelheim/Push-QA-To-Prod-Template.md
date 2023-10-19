1. List of servers involved (where following steps will be executed).

Prod-NJ-web01.boehringer-Ingelheim.com
Prod-NJ-web02.boehringer-Ingelheim.com

2. Record website status before change.

curl -IL zdrowie-kota-seniora.pl

3. Login into server (one at a time) using sslogin.

sslogin --comment=CHG0269670 --ip=64.106.196.4
sslogin --comment=CHG0269670 --ip=64.106.196.5

4. Create a file /tmp/CHG0269670 and add below lines (file/folders path) in it. 
vim /tmp/CHG0269670 

web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600.eot
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600.svg
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600.ttf
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600.woff
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600.woff2
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600italic.eot
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600italic.svg
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600italic.ttf
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600italic.woff
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-600italic.woff2
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-italic.eot
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-italic.svg
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-italic.ttf
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-italic.woff
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-italic.woff2
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-regular.eot
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-regular.svg
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-regular.ttf
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-regular.woff
web/public/sites/all/themes/catsenior/fonts/open-sans-v34-latin-regular.woff2
web/public/sites/all/themes/catsenior/styles/screen.css
web/public/sites/all/themes/catsenior/templates/html.tpl.php
web/public/sites/all/themes/catsenior/templates/nodes/node--home.tpl.php
web/public/sites/all/themes/catsenior/template.php
web/public/sites/all/themes/catsenior/templates/views/top-banner/views-view-fields--top-banner–block.tpl.php

5. Execute following command to pull file from QA to Prod. It will perform necessary backup under /backups.
         $ files-deploy zdrowie-kota-seniora.pl CHG0269670

6. Verify rsync output for any errors and take appropriate action to resolve it.
       If need to run script again then rename backup under /backups otherwise it will get overwrite.

### Use this to complement the SOW creation

Documentation of Impact
    Files will be pushed to listed servers

Back out Procedure
    Restore from the backup taken by the files-deploy script under /backups

Back out Procedure
    Verify curl output returns same value as before.
    Rest of the verification will be performed by customer team.
