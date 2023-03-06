#!/bin/bash
# sample script for running unit tests in docker.  This functionality should be moved to a rake task
#
#docker-compose build
#docker-compose up --exit-code-from unit-test

docker-compose run --rm api bundle exec rake test TESTOPTS='-v'
#docker-compose run --rm apibundle exec rake test TESTOPTS='-v' TEST='./test/controllers/test_annotator_controller.rb'
docker-compose stop
