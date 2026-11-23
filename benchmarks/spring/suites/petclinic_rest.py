"""spring-petclinic-rest with its JDBC repository layer on PostgreSQL (profiles `postgres,jdbc`).

The cases run in order against one process and one fresh database that the application initialises itself
(`spring.sql.init.mode=always` with the upstream schema.sql and data.sql), so created ids and later reads depend on
earlier cases: the order is part of the contract.

Covered: every v1 resource (owners and their pets and visits, pets, visits, pet types, specialties, vets, users),
the v2 paged listings, Bean Validation failures rendered by the application's ProblemDetail advice, Spring MVC's
failures before the handler (type mismatch, unreadable body, unknown path, wrong method), CORS from
`@CrossOrigin`, the Spring Security response headers, the root redirect, and the actuator endpoints.

Not covered: the springdoc-openapi endpoints (`/v3/api-docs`, `/swagger-ui`). springdoc is a third-party library
outside Phase 1's port list (ADR-030, Phases); its output is thousands of lines generated from openapi.yml.
Validation failures use one invalid field per request, because Hibernate Validator reports several violations of
one object in no defined order.
"""
from springsuite import Case

API = '/petclinic/api'
PROBLEM = {'timestamp': 'instant'}
ORIGIN = {'Origin': 'http://client.example'}

OWNER = {'firstName': 'Ada', 'lastName': 'Lovelace', 'address': '12 St James Sq.', 'city': 'London',
         'telephone': '0123456789'}
PET = {'name': 'Babbage', 'birthDate': '2020-02-02', 'type': {'id': 2, 'name': 'dog'}}
VISIT = {'date': '2026-01-15', 'description': 'annual check-up'}


def owner(**changes):
    return dict(OWNER, **changes)


def pet(**changes):
    return dict(PET, **changes)


CASES = [
    # Root and actuator
    Case('root redirects to the Swagger UI', 'GET', '/petclinic/'),
    Case('actuator links', 'GET', '/petclinic/actuator'),
    Case('actuator health', 'GET', '/petclinic/actuator/health'),
    Case('actuator liveness group', 'GET', '/petclinic/actuator/health/liveness'),
    Case('actuator readiness group', 'GET', '/petclinic/actuator/health/readiness'),
    Case('actuator endpoint that is not exposed', 'GET', '/petclinic/actuator/info', volatile=PROBLEM),
    Case('actuator health with an explicit Accept', 'GET', '/petclinic/actuator/health',
         headers={'Accept': 'application/json'}),

    # Reads of the seeded data
    Case('list owners', 'GET', f'{API}/owners'),
    Case('owners by last name', 'GET', f'{API}/owners?lastName=Davis'),
    Case('owners by last name prefix', 'GET', f'{API}/owners?lastName=Da'),
    Case('owners by an unknown last name', 'GET', f'{API}/owners?lastName=Nobody'),
    Case('owner with pets and visits', 'GET', f'{API}/owners/6'),
    Case('unknown owner', 'GET', f'{API}/owners/999'),
    Case('owner id that is not a number', 'GET', f'{API}/owners/abc', volatile=PROBLEM),
    Case('owner pet', 'GET', f'{API}/owners/6/pets/7'),
    Case('pet of another owner', 'GET', f'{API}/owners/1/pets/7'),
    Case('list pets', 'GET', f'{API}/pets'),
    Case('pet', 'GET', f'{API}/pets/8'),
    Case('unknown pet', 'GET', f'{API}/pets/999'),
    Case('list visits', 'GET', f'{API}/visits'),
    Case('visit', 'GET', f'{API}/visits/2'),
    Case('unknown visit', 'GET', f'{API}/visits/999'),
    Case('list pet types', 'GET', f'{API}/pettypes'),
    Case('pet type', 'GET', f'{API}/pettypes/3'),
    Case('unknown pet type', 'GET', f'{API}/pettypes/999'),
    Case('list specialties', 'GET', f'{API}/specialties'),
    Case('specialty', 'GET', f'{API}/specialties/2'),
    Case('unknown specialty', 'GET', f'{API}/specialties/999'),
    Case('list vets', 'GET', f'{API}/vets'),
    Case('vet with specialties', 'GET', f'{API}/vets/3'),
    Case('unknown vet', 'GET', f'{API}/vets/999'),

    # v2 paged listings
    Case('v2 owners default page', 'GET', f'{API}/v2/owners'),
    Case('v2 owners page and size', 'GET', f'{API}/v2/owners?page=1&size=3'),
    Case('v2 owners past the end', 'GET', f'{API}/v2/owners?page=9&size=5'),
    Case('v2 owners by last name', 'GET', f'{API}/v2/owners?lastName=Davis&size=1'),
    Case('v2 pets page', 'GET', f'{API}/v2/pets?page=2&size=4'),
    Case('v2 size below the minimum', 'GET', f'{API}/v2/pets?size=0', volatile=PROBLEM),

    # Owners: create, validate, update, delete
    Case('create owner', 'POST', f'{API}/owners', body=OWNER),
    Case('created owner reads back', 'GET', f'{API}/owners/11'),
    Case('create owner with UTF-8 names', 'POST', f'{API}/owners',
         body=owner(firstName='Zoë', lastName="O'Brien-Núñez", city='São Paulo')),
    Case('create owner: telephone with letters', 'POST', f'{API}/owners', body=owner(telephone='01234abcde'),
         volatile=PROBLEM),
    Case('create owner: blank city', 'POST', f'{API}/owners', body=owner(city='   '), volatile=PROBLEM),
    Case('create owner: missing first name', 'POST', f'{API}/owners',
         body={k: v for k, v in OWNER.items() if k != 'firstName'}, volatile=PROBLEM),
    Case('create owner: first name with digits', 'POST', f'{API}/owners', body=owner(firstName='Ada2'),
         volatile=PROBLEM),
    Case('create owner: malformed JSON', 'POST', f'{API}/owners', body='{"firstName": "Ada",', volatile=PROBLEM),
    Case('create owner: wrong content type', 'POST', f'{API}/owners', body='firstName=Ada',
         headers={'Content-Type': 'application/x-www-form-urlencoded'}, volatile=PROBLEM),
    Case('update owner', 'PUT', f'{API}/owners/11', body=owner(city='Marylebone', telephone='0987654321')),
    Case('updated owner reads back', 'GET', f'{API}/owners/11'),
    Case('update unknown owner', 'PUT', f'{API}/owners/999', body=OWNER),
    Case('update owner: last name with four parts', 'PUT', f'{API}/owners/11', body=owner(lastName='Van Der Berg Smith'),
         volatile=PROBLEM),

    # Pets of an owner
    Case('add pet to owner', 'POST', f'{API}/owners/11/pets', body=PET),
    Case('added pet reads back through the owner', 'GET', f'{API}/owners/11/pets/14'),
    Case('add pet to unknown owner', 'POST', f'{API}/owners/999/pets', body=PET),
    Case('add pet: birth date in the future', 'POST', f'{API}/owners/11/pets', body=pet(birthDate='2999-01-01'),
         volatile=PROBLEM),
    Case('add pet: birth date older than 50 years', 'POST', f'{API}/owners/11/pets', body=pet(birthDate='1900-01-01'),
         volatile=PROBLEM),
    Case('add pet: blank name', 'POST', f'{API}/owners/11/pets', body=pet(name=' '), volatile=PROBLEM),
    Case('add pet: unknown pet type', 'POST', f'{API}/owners/11/pets', body=pet(type={'id': 999, 'name': 'dragon'}),
         volatile=PROBLEM),
    Case('update owner pet', 'PUT', f'{API}/owners/11/pets/14',
         body=pet(name='Analytical', type={'id': 1, 'name': 'cat'})),
    Case('update pet of unknown owner', 'PUT', f'{API}/owners/999/pets/14', body=PET),
    Case('add visit through the owner', 'POST', f'{API}/owners/11/pets/14/visits', body=VISIT),
    Case('owner with the new pet and visit', 'GET', f'{API}/owners/11'),

    # Pets
    Case('update pet', 'PUT', f'{API}/pets/14',
         body={'id': 14, 'name': 'Engine', 'birthDate': '2021-03-03', 'type': {'id': 5, 'name': 'bird'}, 'visits': []}),
    Case('updated pet reads back', 'GET', f'{API}/pets/14'),
    Case('update unknown pet', 'PUT', f'{API}/pets/999',
         body={'id': 999, 'name': 'Ghost', 'birthDate': '2021-03-03', 'type': {'id': 5, 'name': 'bird'}, 'visits': []}),

    # Visits
    Case('create visit', 'POST', f'{API}/visits', body=dict(VISIT, petId=1, description='first visit for Leo')),
    Case('create visit: whitespace description', 'POST', f'{API}/visits', body=dict(VISIT, petId=1, description=' '),
         volatile=PROBLEM),
    Case('create visit for an unknown pet', 'POST', f'{API}/visits', body=dict(VISIT, petId=999), volatile=PROBLEM),
    Case('update visit', 'PUT', f'{API}/visits/6', body={'date': '2026-02-01', 'description': 'follow-up'}),
    Case('updated visit reads back', 'GET', f'{API}/visits/6'),
    Case('update unknown visit', 'PUT', f'{API}/visits/999', body={'date': '2026-02-01', 'description': 'x'}),
    Case('delete visit', 'DELETE', f'{API}/visits/6'),
    Case('delete unknown visit', 'DELETE', f'{API}/visits/6'),

    # Pet types
    Case('create pet type', 'POST', f'{API}/pettypes', body={'name': 'ferret'}),
    Case('create pet type: name starting with a digit', 'POST', f'{API}/pettypes', body={'name': '9cats'},
         volatile=PROBLEM),
    Case('update pet type without an id', 'PUT', f'{API}/pettypes/7', body={'name': 'weasel'}, volatile=PROBLEM),
    Case('update pet type', 'PUT', f'{API}/pettypes/7', body={'id': 7, 'name': 'weasel'}),
    Case('updated pet type reads back', 'GET', f'{API}/pettypes/7'),
    Case('update unknown pet type', 'PUT', f'{API}/pettypes/999', body={'id': 999, 'name': 'weasel'}),
    Case('delete pet type', 'DELETE', f'{API}/pettypes/7'),
    Case('delete pet type in use deletes its pets', 'DELETE', f'{API}/pettypes/6'),
    Case('delete unknown pet type', 'DELETE', f'{API}/pettypes/7'),

    # Specialties
    Case('create specialty', 'POST', f'{API}/specialties', body={'name': 'oncology'}),
    Case('create specialty: name with digits', 'POST', f'{API}/specialties', body={'name': '9lives'},
         volatile=PROBLEM),
    Case('update specialty', 'PUT', f'{API}/specialties/4', body={'name': 'cardiology'}),
    Case('updated specialty reads back', 'GET', f'{API}/specialties/4'),
    Case('update unknown specialty', 'PUT', f'{API}/specialties/999', body={'name': 'cardiology'}),

    # Vets
    Case('create vet with a specialty', 'POST', f'{API}/vets',
         body={'firstName': 'Grace', 'lastName': 'Hopper', 'specialties': [{'id': 4, 'name': 'cardiology'}]}),
    Case('create vet: last name too long', 'POST', f'{API}/vets',
         body={'firstName': 'Grace', 'lastName': 'H' * 31, 'specialties': []}, volatile=PROBLEM),
    Case('update vet', 'PUT', f'{API}/vets/7',
         body={'firstName': 'Grace', 'lastName': 'Brewster', 'specialties': [{'id': 1, 'name': 'radiology'}]}),
    Case('updated vet reads back', 'GET', f'{API}/vets/7'),
    Case('update unknown vet', 'PUT', f'{API}/vets/999', body={'firstName': 'A', 'lastName': 'B', 'specialties': []}),
    Case('delete vet', 'DELETE', f'{API}/vets/7'),
    Case('delete unknown vet', 'DELETE', f'{API}/vets/7'),
    Case('delete specialty', 'DELETE', f'{API}/specialties/4'),
    Case('delete unknown specialty', 'DELETE', f'{API}/specialties/4'),

    # Users
    Case('create user', 'POST', f'{API}/users',
         body={'username': 'clerk', 'password': 'secret', 'enabled': True, 'roles': [{'name': 'ROLE_OWNER_ADMIN'}]}),
    Case('create user: role without the ROLE_ prefix', 'POST', f'{API}/users',
         body={'username': 'clerk3', 'password': 'secret', 'enabled': True, 'roles': [{'name': 'OWNER_ADMIN'}]},
         volatile=PROBLEM),
    Case('create user: missing roles', 'POST', f'{API}/users',
         body={'username': 'clerk2', 'password': 'secret', 'enabled': True}, volatile=PROBLEM),

    # Deletes
    Case('delete pet', 'DELETE', f'{API}/pets/14'),
    Case('delete unknown pet', 'DELETE', f'{API}/pets/14'),
    Case('delete owner', 'DELETE', f'{API}/owners/12'),
    Case('delete unknown owner', 'DELETE', f'{API}/owners/12'),
    Case('owners after the changes', 'GET', f'{API}/owners'),

    # Failures before the handler
    Case('unknown API path', 'GET', f'{API}/nothing-here', volatile=PROBLEM),
    Case('wrong method', 'PATCH', f'{API}/owners/1', body={}, volatile=PROBLEM),
    Case('path outside the context path', 'GET', '/api/owners', volatile=PROBLEM),

    # CORS (@CrossOrigin(exposedHeaders = "errors, content-type"))
    Case('CORS simple request', 'GET', f'{API}/pettypes/2', headers=ORIGIN),
    Case('CORS preflight', 'OPTIONS', f'{API}/owners',
         headers=dict(ORIGIN, **{'Access-Control-Request-Method': 'POST',
                                 'Access-Control-Request-Headers': 'content-type'})),
    Case('CORS preflight for a method that is not mapped', 'OPTIONS', f'{API}/owners',
         headers=dict(ORIGIN, **{'Access-Control-Request-Method': 'PATCH'})),
]
