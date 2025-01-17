# Potential Useful SQL Queries

## Fence Database

### Get All User Access by Username and Project.auth_id, include Authorization Source name and Identity Provider
```sql
select "User".username, project.auth_id, authorization_provider.name as authz_provider, identity_provider.name as idp from access_privilege INNER JOIN "User" on access_privilege.user_id="User".id INNER JOIN project on access_privilege.project_id=project.id INNER JOIN authorization_provider on access_privilege.provider_id=authorization_provider.id INNER JOIN identity_provider on "User".idp_id=identity_provider.id ORDER BY "User".username;
```

Example output:
```console
             username             |  auth_id  |  authz_provider  |  idp   |
----------------------------------+-----------+------------------+--------+
 USER_A                           | test1     | fence            | ras    |
 USER_A                           | test2     | dbGaP            | ras    |
 USER_B                           | test1     | fence            | google |
 USER_B                           | test2     | fence            | google |
 USER_B                           | test3     | dbGaP            | google |
 USER_C                           | test2     | dbGaP            | ras    |

```

### Get Bucket Name(s) and Google Bucket Access Groups associated with Project.auth_id
Particularly useful with commons that have buckets in Google.

```sql
select bucket.name, project.auth_id, google_bucket_access_group.email from project_to_bucket INNER JOIN project ON project.id=project_to_bucket.project_id INNER JOIN bucket ON bucket.id=project_to_bucket.bucket_id INNER JOIN google_bucket_access_group ON bucket.id=google_bucket_access_group.bucket_id ORDER BY project.auth_id;
```

Example output:
```console
                 name                    |  auth_id  |                                 email                            
-----------------------------------------+-----------+-------------------------------------------------------------------
 test-bucket-with-data                   | test      | test-bucket-with-data_read_gbag@test.datacommons.io
 test-bucket-with-data                   | test      | test-bucket-with-data_write_gbag@test.datacommons.io
```

### Get User Proxy Google Groups within Google Bucket Access Group specified

```sql
select google_proxy_group.email, google_bucket_access_group.email from google_proxy_group_to_google_bucket_access_group INNER JOIN google_proxy_group ON google_proxy_group_to_google_bucket_access_group.proxy_group_id=google_proxy_group.id INNER JOIN google_bucket_access_group ON google_proxy_group_to_google_bucket_access_group.access_group_id=google_bucket_access_group.id where google_bucket_access_group.email='prefix_phs0000123.c1_read_gbag@example.com';
```

Example output:
```console
                              email                              |                        email
-----------------------------------------------------------------+-----------------------------------------------------
 prefix-username1-1@example.com                                  | prefix_phs0000123.c1_read_gbag@example.com
 prefix-username2-2@example.com                                  | prefix_phs0000123.c1_read_gbag@example.com
```

### Get Registered Google Service Account(s) Project Access and Expiration
To determine which user service accounts currently have access to controlled data (and their associated Google Project).

```sql
SELECT DISTINCT user_service_account.google_project_id, user_service_account.email, project.auth_id, service_account_to_google_bucket_access_group.expires from service_account_to_google_bucket_access_group
INNER JOIN user_service_account ON service_account_to_google_bucket_access_group.service_account_id=user_service_account.id
INNER JOIN service_account_access_privilege ON user_service_account.id=service_account_access_privilege.service_account_id
INNER JOIN project ON service_account_access_privilege.project_id=project.id ORDER BY user_service_account.google_project_id;
```

Example output:
```console
  google_project_id   |                               email                               |  auth_id  |  expires   
----------------------+-------------------------------------------------------------------+-----------+------------
 tmp-test             | 1234567890-compute@developer.gserviceaccount.com                  | test1     | 1543254638
 tmp-test             | test-service-account@tmp-test.iam.gserviceaccount.com             | test2     | 1543254614
 tmp-test             | test-service-account@tmp-test.iam.gserviceaccount.com             | test1     | 1543254614
 foobar               | blahblahblahb@foobar.iam.gserviceaccount.com                      | test1     | 1543254897

 
```

## Arborist Database 

### Get access by username and resource paths

```sql
SELECT policies.name, path FROM (SELECT * FROM usr INNER JOIN usr_policy ON usr_policy.usr_id = usr.id WHERE usr.name = 'test@gmail.com') AS policies JOIN policy_resource ON policy_resource.policy_id = policies.policy_id JOIN resource ON resource.id = policy_resource.resource_id;
```

Replace `test@gmail.com` with whatever, or just remove the WHERE to get everything. This will *not* include policies granted by a user's group membership.

Example output: 
```
          name           |               path
-------------------------+----------------------------------
 test@gmail.com          | workspace
 test@gmail.com          | prometheus
 test@gmail.com          | data_file
 test@gmail.com          | programs.jnkns
 test@gmail.com          | programs.jnkns.projects.jenkins
```
