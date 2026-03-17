TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test fmt

test:
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }"

fmt:
	@stylua .
