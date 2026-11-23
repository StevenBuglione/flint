"""gs-relational-data-access: a CommandLineRunner that creates a table with JdbcTemplate, batch-inserts four
customers, queries two back by first name, logs each step and exits 0.

The observable contract is the exit code and the application's own log events in Spring Boot's console format.
"""
from springsuite import CommandSuite

SUITE = CommandSuite(logger='c.e.r.RelationalDataAccessApplication', timeout=60)
