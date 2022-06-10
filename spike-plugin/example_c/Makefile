plugin.so: plugin.c
	@gcc -I../../repo/riscv-isa-sim -shared -o plugin.so -Wall -Werror -fPIC plugin.c -lrt

.PHONY: clean
clean:
	@rm -f plugin.so
