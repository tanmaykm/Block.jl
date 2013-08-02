Blocks
======
A framework to:
- represent chunks of entities
- represent processor affinities of the chunks
- compose actions on chunks by chaining functions 
- do map and reduce operations with the above

It represents a typical pattern observed across several types of parallel processing tasks. The Blocks framework can be leveraged to build convenience APIs for parallelizing such tasks. The composability of Blocks lends to a convenient and compact syntax.

As examples of its utility, it has been used to implement chunked and distributed operations on disk files, HDFS files, IO streams, arrays, matrices, and dataframes. Some of them are included in the Blocks module while the rest are available as sub modules of Blocks:
- Blocks.Hadoop
- Blocks.DDataFrames
- Blocks.MatOp


### Creating Blocks
#### Disk Files
````
using Blocks

Block(file::File, nblocks::Int=0)
    Where nblocks is the number of chunks to divide the file into.
    Number of chunks (nblocks) defaults to number of worker processes.
    Each chunk is represented as the file and the byte range.
    Assumes that the file is available at all processors and chunks can be processed anywhere.
````

#### HDFS Files
````
using Blocks
using Blocks.Hadoop

Block(file::HdfsURL)
    Each chunk is a block in HDFS.
    Processor affinity of each chunk is set to machines where this block has been replicated by HDFS.
````

#### Arrays:
````
using Blocks

Block(A::Array, dims::Array)
    Chunks created across dimensions specified in dims.
    Chunks are not pre-distributed and any chunk can be processed at any processor.

Block(A::Array, dim::Int, nblocks::Int)
    Chunked to nblocks chunks on dimension dim.
    Chunks are not pre-distributed and any chunk can be processed at any processor.
````

#### Matrix Operations
Parallelized operations on matrices can be represented and executed using Blocks. Module `Blocks.MatOp` provides a set of convenience APIs using the `MatOpBlock` object.

````
julia> using Blocks

julia> using Blocks.MatOp

julia> 

julia> # create two matrices

julia> m1 = rand(Int, 6, 10);

julia> m2 = rand(Int, 10, 6);

julia> 

julia> # create a parallel matrix operation using the two, multiplication in this case

julia> mb = MatOpBlock(m1, m2, :*, 3);

julia> 

julia> # represent that in blocks

julia> blk = Block(mb);

julia> 

julia> # execute the operation

julia> result = op(blk);

julia> 

julia> # verify the result

julia> tr = m1*m2;

julia> 

julia> all(tr .== result)
true
````

#### Streams:
````
using Blocks

Block(stream::Union(IOStream,AsyncStream,IOBuffer,BlockIO), maxsize::Int)
    Iterating on the block thus created would read a chunk of data from `stream`.
    Each chunk will represent a `maxsize` sized data block read from `stream`.

Block(stream::Union(IOStream,AsyncStream,IOBuffer,BlockIO), approxsize::Int, dlm::Char)
    Iterating on the block thus created would read a chunk of data from `stream`.
    Each chunk is  approximately of size `approxsize` and ends with the `dlm` character.
````

#### Distributed DataFrames:
Blocks introduces a distributed `DataFrame` type named `DDataFrame`. It holds referenced to multiple remote data frames, on multiple processors. A large table can be read in parallel into a DDataFrame by using the special `dreadtable` method. 

````
using Blocks
using Blocks.DDataFrames

dreadtable(filename::String; kwargs...)
dreadtable(blocks::Block; kwargs...)
    Where blocks are created from disk or HDFS files or from streams as described in sections above.
dreadtable(ios::Union(AsyncStream,IOStream), chunk_sz::Int, merge_chunks::Bool=true; kwargs...)
    Where 
        ios is a stream of data
        chunk_sz is the approximate number of bytes to chunk the data into
        merge_chunks indicates whether all chunks on a single processor should be merged. 
        Merging discards positional information but makes the dataframe efficient by having fewer chunks.
````

A `DDataFrame` is easily represented as Blocks. `DDataFrame` has been used with `Blocks` to implement most `DataFrame` operations in a distributed manner. Most methods defined on a DataFrame also work on DDataFrames in a distributed manner using `pmap` and `reduce` to operate on chunks parallely.

````
julia> using Blocks

julia> using Blocks.DDataFrames

julia> dt = dreadtable("test.csv")
100x10 DDataFrame. 2 blocks over 2 processors

julia> head(dt)
6x10 DataFrame:
               x1        x2        x3        x4        x5        x6        x7       x8       x9      x10
[1,]     0.105518  0.173988  0.244224 0.0174508 0.0969595   0.12792  0.316974 0.852373 0.165014 0.886957
[2,]     0.319401 0.0719447 0.0019209  0.285511  0.945343  0.926718  0.162048 0.118748 0.361014 0.611316
[3,]     0.516926  0.473779  0.867099  0.408605  0.579969  0.111174 0.0790296 0.263822 0.073827 0.187637
[4,]     0.579538  0.319672  0.600223  0.707782  0.806437  0.402244  0.670792  0.10981 0.518356 0.604807
[5,]     0.660944  0.648076  0.611529  0.885457  0.550101 0.0634721  0.152263 0.855182 0.408393 0.473676
[6,]    0.0324734   0.22839  0.812387   0.59965  0.143703    0.1337  0.945763 0.296137 0.875762 0.989037

julia> colsums(dt)
1x10 DataFrame:
             x1      x2      x3      x4      x5      x6     x7      x8      x9     x10
[1,]    46.1597 41.9286 51.4197 50.1906 48.2623 44.5622 50.914 50.7266 44.1346 51.1001

julia> all(dt+dt .== 2*dt)
true
````

### Composing Actions on Blocks
Functions can be chained and then applied on to chunks in a block with a `pmap` or `pmapreduce`. The Julia notation `|>` is used to indicate chaining. For example to read a block of DataFrame from a chunk of a disk file:
````
b = Block(File(filename)) |> as_io |> as_recordio |> as_dataframe
````
Each function in the chain works on the output of the previous function.

Following is a list of functions provided in the package. User specified functions can be chained in as well:
- `as_io`: creates an `IO` instance from streams or files
- `as_recordio`: creates an `IO` instance from streams or files where begin and end positions are adjusted to the boundaries of delimited records
- `as_lines`: creates an array of lines from `IO`
- `as_bufferedio`: creates buffered `IO` from any other `IO`
- `as_bytearray`: creates bytearray from any `IO`
- `as_dataframe`: creates a dataframe from any `IO`


### Map and Reduces on Blocks
Regular Julia map-reduce methods can be used on blocks. The map methods receive the chunks as they have been processed by the chain of actions composed into the Blocks.

````
julia> ba = Block([1:100], 1, 10);

julia> pmap(x->sum(x), ba)
10-element Any Array:
  55
 155
 255
 355
 455
 555
 655
 755
 855
 955

julia> pmapreduce(x->sum(x), +, ba)
5050

julia> ba = Block([1:100], 1, 10);

julia> map(x->sum(x), ba)
10-element Any Array:
  55
 155
 255
 355
 455
 555
 655
 755
 855
 955

julia> mapreduce(x->sum(x), +, ba)
5050
````


### Sample Use Cases
#### Sorting Disk Files
TODO
#### Distributed DataFrame from streaming data
TODO
#### Continuous summarization of streaming data using DataFrames
TODO

