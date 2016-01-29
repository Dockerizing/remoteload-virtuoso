# RDF Store Importer - Docker Container

Docker container to import data into  RDF stores (currently only [Virtuoso Opensource](http://virtuoso.openlinksw.com/dataspace/doc/dav/wiki/Main)).

## Usage

Clone this repository and build with:

`docker build -t loader .`

Create a folder `import/` and insert some RDF files (file format can be ttl, nt, ...) to import. 

The graph will be extracted from filename (example: test.nt goes to http://test/). If you need a specific graph, just create a file `[filename].[filextension].graph` which only contains the base URI as string.

*Example:*

`import/my-data.nt` (RDF-Data)

`import/my-data.nt.graph` (Graph, content: http://my-graph-uri/)

### Run

`docker run -v $PWD/import:/import_store -e "STORE_1=uri=>http://ip-addr:8890/sparql user=>dba pwd=>dba" loader`

The `-v` parameter creates a volume to the import folder.

With the `-e` parameter stores can be passed to the container. Change the uri to your local requirements.

Its also possible to give more than one store, to import data. Example:

```
docker run -v $PWD/import:/import_store \
    -e "STORE_1=uri=>http://ip-addr-1:8890/sparql user=>dba pwd=>dba" \
    -e "STORE_2=uri=>http://ip-addr-2:8890/sparql user=>dba pwd=>dba" \
    loader
```