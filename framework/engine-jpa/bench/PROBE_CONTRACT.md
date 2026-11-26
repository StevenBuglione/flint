# flint:engine-jpa size probe

The fixture and control use the same PostgreSQL connection options, prepared SQL and JDBC cursor. Both materialize an `Owner` from the projection `name, id`, check the row and print `One` followed by a newline. The fixture registers an inherited-ordinal-compatible mapping and calls the shared materializer. The control fills the same fields directly and checks SQL NULL as it reads.

`tools/measure_builds.py --framework-sizes --framework engine-jpa` compares the larger O3 and Oz loadable-section difference with the same JDBC dependencies. It counts DMD instances in the provider library and its probe. For a behavior check, pass the JDBC URL, user and password of a disposable pinned PostgreSQL peer to each executable. The linked DMD and LDC fixture under `fixtures/postgres` exercises projection order, lifecycle callbacks and transaction integration on that peer.
