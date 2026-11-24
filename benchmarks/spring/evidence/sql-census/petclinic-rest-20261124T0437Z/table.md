| case | java: data / txn / parse (unnamed) / exec | flint: data / txn / parse (unnamed) / exec | go: data / txn / parse (unnamed) / exec | differs from Java |
|---|---|---|---|---|
| GET /petclinic/ (root redirects to the Swagger UI) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| GET /petclinic/actuator (actuator links) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| GET /petclinic/actuator/health (actuator health) | 2 / 0 / 0 (0) / 2 | 0 / 0 / 0 (0) / 0 | 1 / 0 / 0 (0) / 1 | flint: data {} vs {'other': 2}; go: data {'other': 1} vs {'other': 2} |
| GET /petclinic/actuator/health/liveness (actuator liveness group) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| GET /petclinic/actuator/health/readiness (actuator readiness group) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| GET /petclinic/actuator/info (actuator endpoint that is not exposed) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| GET /petclinic/actuator/health (actuator health with an explicit Accept) | 1 / 0 / 0 (0) / 1 | 0 / 0 / 0 (0) / 0 | 1 / 0 / 0 (0) / 1 | flint: data {} vs {'other': 1} |
| GET /petclinic/api/owners (list owners) | 21 / 2 / 12 (9) / 23 | 21 / 2 / 5 (2) / 23 | 21 / 0 / 3 (0) / 21 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/owners?lastName=Davis (owners by last name) | 5 / 2 / 1 (1) / 7 | 5 / 2 / 3 (2) / 7 | 5 / 0 / 1 (0) / 5 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/owners?lastName=Da (owners by last name prefix) | 5 / 2 / 1 (1) / 7 | 5 / 2 / 2 (2) / 7 | 5 / 0 / 0 (0) / 5 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/owners?lastName=Nobody (owners by an unknown last name) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/owners/6 (owner with pets and visits) | 3 / 2 / 1 (1) / 5 | 3 / 2 / 3 (2) / 5 | 3 / 0 / 1 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/owners/999 (unknown owner) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/owners/abc (owner id that is not a number) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| GET /petclinic/api/owners/6/pets/7 (owner pet) | 3 / 2 / 1 (1) / 5 | 3 / 2 / 2 (2) / 5 | 3 / 0 / 0 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/owners/1/pets/7 (pet of another owner) | 3 / 2 / 1 (1) / 5 | 3 / 2 / 2 (2) / 5 | 3 / 0 / 0 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/pets (list pets) | 3 / 2 / 2 (2) / 5 | 3 / 2 / 4 (2) / 5 | 3 / 0 / 2 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/pets/8 (pet) | 4 / 2 / 2 (1) / 6 | 4 / 2 / 3 (2) / 6 | 4 / 0 / 1 (0) / 4 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/pets/999 (unknown pet) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/visits (list visits) | 13 / 2 / 9 (9) / 15 | 13 / 2 / 5 (2) / 15 | 13 / 0 / 3 (0) / 13 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/visits/2 (visit) | 4 / 2 / 3 (1) / 6 | 4 / 2 / 3 (2) / 6 | 4 / 0 / 1 (0) / 4 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/visits/999 (unknown visit) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/pettypes (list pet types) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 3 (2) / 3 | 1 / 0 / 1 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/pettypes/3 (pet type) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/pettypes/999 (unknown pet type) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/specialties (list specialties) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 3 (2) / 3 | 1 / 0 / 1 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/specialties/2 (specialty) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 3 (2) / 3 | 1 / 0 / 1 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/specialties/999 (unknown specialty) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/vets (list vets) | 8 / 2 / 7 (6) / 10 | 8 / 2 / 4 (2) / 10 | 8 / 0 / 2 (0) / 8 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/vets/3 (vet with specialties) | 3 / 2 / 2 (2) / 5 | 3 / 2 / 3 (2) / 5 | 3 / 0 / 1 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/vets/999 (unknown vet) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/v2/owners (v2 owners default page) | 22 / 2 / 2 (2) / 24 | 22 / 2 / 4 (2) / 24 | 22 / 0 / 2 (0) / 22 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/v2/owners?page=1&size=3 (v2 owners page and size) | 8 / 2 / 2 (2) / 10 | 8 / 2 / 2 (2) / 10 | 8 / 0 / 0 (0) / 8 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/v2/owners?page=9&size=5 (v2 owners past the end) | 2 / 2 / 2 (2) / 4 | 2 / 2 / 2 (2) / 4 | 2 / 0 / 0 (0) / 2 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/v2/owners?lastName=Davis&size=1 (v2 owners by last name) | 4 / 2 / 2 (2) / 6 | 4 / 2 / 4 (2) / 6 | 4 / 0 / 2 (0) / 4 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/v2/pets?page=2&size=4 (v2 pets page) | 4 / 2 / 3 (3) / 6 | 4 / 2 / 4 (2) / 6 | 4 / 0 / 2 (0) / 4 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/v2/pets?size=0 (v2 size below the minimum) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners (create owner) | 3 / 2 / 3 (3) / 5 | 3 / 2 / 5 (2) / 5 | 1 / 0 / 1 (0) / 1 | go: data {'insert': 1} vs {'select': 2, 'insert': 1}; go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/owners/11 (created owner reads back) | 3 / 2 / 0 (0) / 5 | 3 / 2 / 2 (2) / 5 | 3 / 0 / 0 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/owners (create owner with UTF-8 names) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/owners (create owner: telephone with letters) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners (create owner: blank city) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners (create owner: missing first name) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners (create owner: first name with digits) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners (create owner: malformed JSON) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners (create owner: wrong content type) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| PUT /petclinic/api/owners/11 (update owner) | 4 / 4 / 1 (1) / 8 | 4 / 4 / 5 (4) / 8 | 4 / 0 / 1 (0) / 4 | go: txn {} vs {'begin': 2, 'commit': 2} |
| GET /petclinic/api/owners/11 (updated owner reads back) | 3 / 2 / 0 (0) / 5 | 3 / 2 / 2 (2) / 5 | 3 / 0 / 0 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| PUT /petclinic/api/owners/999 (update unknown owner) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| PUT /petclinic/api/owners/11 (update owner: last name with four parts) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners/11/pets (add pet to owner) | 7 / 4 / 3 (3) / 11 | 7 / 4 / 5 (4) / 11 | 5 / 2 / 1 (0) / 7 | go: data {'select': 4, 'insert': 1} vs {'select': 6, 'insert': 1}; go: txn {'begin': 1, 'commit': 1} vs {'begin': 2, 'commit': 2} |
| GET /petclinic/api/owners/11/pets/14 (added pet reads back through the owner) | 3 / 2 / 0 (0) / 5 | 3 / 2 / 2 (2) / 5 | 3 / 0 / 0 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/owners/999/pets (add pet to unknown owner) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/owners/11/pets (add pet: birth date in the future) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners/11/pets (add pet: birth date older than 50 years) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners/11/pets (add pet: blank name) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/owners/11/pets (add pet: unknown pet type) | 4 / 4 / 1 (0) / 8 | 4 / 4 / 4 (4) / 8 | 4 / 2 / 0 (0) / 6 | go: txn {'begin': 1, 'rollback': 1} vs {'begin': 2, 'commit': 1, 'rollback': 1} |
| PUT /petclinic/api/owners/11/pets/14 (update owner pet) | 9 / 6 / 2 (2) / 15 | 9 / 6 / 7 (6) / 15 | 9 / 2 / 1 (0) / 11 | go: txn {'begin': 1, 'commit': 1} vs {'begin': 3, 'commit': 3} |
| PUT /petclinic/api/owners/999/pets/14 (update pet of unknown owner) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/owners/11/pets/14/visits (add visit through the owner) | 3 / 2 / 3 (3) / 5 | 3 / 2 / 3 (2) / 5 | 1 / 0 / 1 (0) / 1 | go: data {'insert': 1} vs {'select': 2, 'insert': 1}; go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/owners/11 (owner with the new pet and visit) | 3 / 2 / 0 (0) / 5 | 3 / 2 / 2 (2) / 5 | 3 / 0 / 0 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| PUT /petclinic/api/pets/14 (update pet) | 6 / 4 / 2 (2) / 10 | 6 / 4 / 4 (4) / 10 | 6 / 2 / 0 (0) / 8 | go: txn {'begin': 1, 'commit': 1} vs {'begin': 2, 'commit': 2} |
| GET /petclinic/api/pets/14 (updated pet reads back) | 4 / 2 / 1 (0) / 6 | 4 / 2 / 2 (2) / 6 | 4 / 0 / 0 (0) / 4 | go: txn {} vs {'begin': 1, 'commit': 1} |
| PUT /petclinic/api/pets/999 (update unknown pet) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/visits (create visit) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/visits (create visit: whitespace description) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/visits (create visit for an unknown pet) | 0 / 2 / 1 (1) / 2 | 0 / 2 / 2 (2) / 2 | 0 / 0 / 0 (0) / 0 | go: txn {} vs {'begin': 1, 'rollback': 1} |
| PUT /petclinic/api/visits/6 (update visit) | 5 / 4 / 2 (2) / 9 | 5 / 4 / 5 (4) / 9 | 5 / 0 / 1 (0) / 5 | go: txn {} vs {'begin': 2, 'commit': 2} |
| GET /petclinic/api/visits/6 (updated visit reads back) | 4 / 2 / 1 (1) / 6 | 4 / 2 / 2 (2) / 6 | 4 / 0 / 0 (0) / 4 | go: txn {} vs {'begin': 1, 'commit': 1} |
| PUT /petclinic/api/visits/999 (update unknown visit) | 1 / 2 / 1 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| DELETE /petclinic/api/visits/6 (delete visit) | 5 / 2 / 1 (1) / 7 | 5 / 2 / 3 (2) / 7 | 5 / 2 / 1 (0) / 7 |  |
| DELETE /petclinic/api/visits/6 (delete unknown visit) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 2 / 0 (0) / 3 |  |
| POST /petclinic/api/pettypes (create pet type) | 3 / 2 / 3 (3) / 5 | 3 / 2 / 3 (2) / 5 | 1 / 0 / 1 (0) / 1 | go: data {'insert': 1} vs {'select': 2, 'insert': 1}; go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/pettypes (create pet type: name starting with a digit) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| PUT /petclinic/api/pettypes/7 (update pet type without an id) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| PUT /petclinic/api/pettypes/7 (update pet type) | 2 / 4 / 1 (1) / 6 | 2 / 4 / 5 (4) / 6 | 2 / 0 / 1 (0) / 2 | go: txn {} vs {'begin': 2, 'commit': 2} |
| GET /petclinic/api/pettypes/7 (updated pet type reads back) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| PUT /petclinic/api/pettypes/999 (update unknown pet type) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| DELETE /petclinic/api/pettypes/7 (delete pet type) | 3 / 2 / 2 (2) / 5 | 3 / 2 / 4 (2) / 5 | 3 / 2 / 2 (0) / 5 |  |
| DELETE /petclinic/api/pettypes/6 (delete pet type in use deletes its pets) | 5 / 2 / 4 (4) / 7 | 5 / 2 / 4 (2) / 7 | 5 / 2 / 2 (0) / 7 |  |
| DELETE /petclinic/api/pettypes/7 (delete unknown pet type) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 2 / 0 (0) / 3 |  |
| POST /petclinic/api/specialties (create specialty) | 3 / 2 / 3 (1) / 5 | 3 / 2 / 3 (2) / 5 | 1 / 0 / 1 (0) / 1 | go: data {'insert': 1} vs {'select': 2, 'insert': 1}; go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/specialties (create specialty: name with digits) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| PUT /petclinic/api/specialties/4 (update specialty) | 2 / 4 / 2 (2) / 6 | 2 / 4 / 5 (4) / 6 | 2 / 0 / 1 (0) / 2 | go: txn {} vs {'begin': 2, 'commit': 2} |
| GET /petclinic/api/specialties/4 (updated specialty reads back) | 1 / 2 / 1 (1) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| PUT /petclinic/api/specialties/999 (update unknown specialty) | 1 / 2 / 1 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| POST /petclinic/api/vets (create vet with a specialty) | 6 / 4 / 4 (4) / 10 | 6 / 4 / 8 (4) / 10 | 4 / 2 / 4 (0) / 6 | go: data {'select': 1, 'insert': 2, 'delete': 1} vs {'select': 3, 'insert': 2, 'delete': 1}; go: txn {'begin': 1, 'commit': 1} vs {'begin': 2, 'commit': 2} |
| POST /petclinic/api/vets (create vet: last name too long) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| PUT /petclinic/api/vets/7 (update vet) | 7 / 6 / 6 (6) / 13 | 7 / 6 / 7 (6) / 13 | 7 / 2 / 1 (0) / 9 | go: txn {'begin': 1, 'commit': 1} vs {'begin': 3, 'commit': 3} |
| GET /petclinic/api/vets/7 (updated vet reads back) | 3 / 2 / 2 (2) / 5 | 3 / 2 / 2 (2) / 5 | 3 / 0 / 0 (0) / 3 | go: txn {} vs {'begin': 1, 'commit': 1} |
| PUT /petclinic/api/vets/999 (update unknown vet) | 1 / 2 / 1 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| DELETE /petclinic/api/vets/7 (delete vet) | 5 / 2 / 3 (2) / 7 | 5 / 2 / 3 (2) / 7 | 5 / 2 / 1 (0) / 7 |  |
| DELETE /petclinic/api/vets/7 (delete unknown vet) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 2 / 0 (0) / 3 |  |
| DELETE /petclinic/api/specialties/4 (delete specialty) | 3 / 2 / 2 (2) / 5 | 3 / 2 / 4 (2) / 5 | 3 / 2 / 2 (0) / 5 |  |
| DELETE /petclinic/api/specialties/4 (delete unknown specialty) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 2 / 0 (0) / 3 |  |
| POST /petclinic/api/users (create user) | 6 / 2 / 4 (4) / 8 | 6 / 2 / 6 (2) / 8 | 4 / 2 / 4 (0) / 6 | go: data {'select': 1, 'insert': 2, 'delete': 1} vs {'select': 3, 'insert': 2, 'delete': 1} |
| POST /petclinic/api/users (create user: role without the ROLE_ prefix) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| POST /petclinic/api/users (create user: missing roles) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| DELETE /petclinic/api/pets/14 (delete pet) | 6 / 4 / 2 (2) / 10 | 6 / 4 / 4 (4) / 10 | 6 / 2 / 0 (0) / 8 | go: txn {'begin': 1, 'commit': 1} vs {'begin': 2, 'commit': 2} |
| DELETE /petclinic/api/pets/14 (delete unknown pet) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| DELETE /petclinic/api/owners/12 (delete owner) | 4 / 2 / 1 (1) / 6 | 4 / 2 / 3 (2) / 6 | 4 / 2 / 1 (0) / 6 |  |
| DELETE /petclinic/api/owners/12 (delete unknown owner) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 2 / 0 (0) / 3 |  |
| GET /petclinic/api/owners (owners after the changes) | 23 / 2 / 1 (1) / 25 | 23 / 2 / 2 (2) / 25 | 23 / 0 / 0 (0) / 23 | go: txn {} vs {'begin': 1, 'commit': 1} |
| GET /petclinic/api/nothing-here (unknown API path) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| PATCH /petclinic/api/owners/1 (wrong method) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| GET /api/owners (path outside the context path) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| GET /petclinic/api/pettypes/2 (CORS simple request) | 1 / 2 / 0 (0) / 3 | 1 / 2 / 2 (2) / 3 | 1 / 0 / 0 (0) / 1 | go: txn {} vs {'begin': 1, 'commit': 1} |
| OPTIONS /petclinic/api/owners (CORS preflight) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
| OPTIONS /petclinic/api/owners (CORS preflight for a method that is not mapped) | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 | 0 / 0 / 0 (0) / 0 |  |
