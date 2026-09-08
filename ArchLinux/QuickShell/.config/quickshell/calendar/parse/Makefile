convert: output/convert.o output/helper.o
	g++ output/convert.o output/helper.o -o convert

output/convert.o: main.cpp helper.h
	g++ -c main.cpp -o output/convert.o

output/helper.o: helper.cpp helper.h
	g++ -c helper.cpp -o output/helper.o

clean:
	rm -f output/*.o
	rm -f convert
