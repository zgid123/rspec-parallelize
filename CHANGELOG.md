# rspec-parallelize

## 0.1.0

- First release: plain `rspec` runs in parallel like Rails' minitest `parallelize`. Workers are forked after boot and pull top-level example groups from a shared queue, results show in RSpec's normal output, and with ActiveRecord each worker gets its own test database. Shows a live progress line in the terminal.
