abstract AbstractBlocks{T,D}

# Blocks can chunk content that is:
#   - non-streaming
#   - accessible in parallel
#   - distributed across processors
type Blocks{T,D} <: AbstractBlocks{T,D}
    source::T
    outtype::Type{D}
    block::Array
    affinity::Array
end

const no_affinity = []

block(b::Blocks) = b.block
affinity(b::Blocks) = b.affinity

function Blocks(a::Array, outtype::Type, by::Int=0, nsplits::Int=0)
    asz = size(a)
    (by == 0) && (by = length(asz))
    (nsplits == 0) && (nsplits = nworkers())
    sz = map(x->1:x, [asz...])
    splits = map((x)->begin sz[by]=x; tuple(sz...); end, Base.splitrange(length(sz[by]), nsplits))
    blocks = [slice(a,x) for x in splits]
    Blocks(a, outtype, blocks, no_affinity)
end

function Blocks(A::Array, outtype::Type, dims::Array)
    isempty(dims) && error("no dimensions specified")
    dimsA = [size(A)...]
    ndimsA = ndims(A)
    alldims = [1:ndimsA]

    blocks = {A}
    if dims != alldims
        otherdims = setdiff(alldims, dims)
        idx = fill!(cell(ndimsA), 1)

        Asliceshape = tuple(dimsA[dims]...)
        itershape   = tuple(dimsA[otherdims]...)
        for d in dims
            idx[d] = 1:size(A,d)
        end
        numblocks = *(itershape...)
        blocks = cell(numblocks)
        blkid = 1
        cartesianmap(itershape) do idxs...
            ia = [idxs...]
            idx[otherdims] = ia
            blocks[blkid] = reshape(A[idx...], Asliceshape)
            blkid += 1
        end
    end
    Blocks(A, outtype, blocks, no_affinity)    
end

function Blocks(f::File, outtype::Type, nsplits::Int=0)
    sz = filesize(f.path)
    (nsplits == 0) && (nsplits = nworkers())
    splits = Base.splitrange(sz, nsplits)
    data = [(f.path, x) for x in splits]
    Blocks(f, outtype, data, no_affinity)
end

# BlockStream can chunk content that is:
#   - streaming
#   - sequential
#   - (and hence available only on one processor)
#type BlockStream{T<:IO,D} <: AbstractBlocks{T,D}
#    source::T
#    outtype::Type{D}
#    block_sz::Int
#    block_delim::Uint8
#end
#
#type BlockStreamIO <: IO
#    b::BlockStream
#    block_pos::Int
#    eof::Bool
#    block_num::Int
#end
#
#const no_delim = 0xff
#
#
#block(b::BlockStream) = b
#affinity(b::BlockStream) = no_affinity
#
#start(b::BlockStream) = BlockStreamIO(b, 0, false, 1)
#function done(b::BlockStream, state::BlockStreamIO)
#    state.eof && (return true)
#    eof(state.b.source) && (return (state.eof = true))
#    false
#end
#function next(b::BlockStream, state::BlockStreamIO)
#    state.block_num += 1
#    state.eof = false
#    state.block_pos = 0
#    (state, state)
#end
#
#
#close(b::BlockStreamIO) = close(b.b.source)
#function eof(state::BlockStreamIO)
#    state.eof && (return true)
#    b = state.b
#    s = b.source
#    eof(s) && (return (state.eof = true))
#
#    if state.block_pos > b.block_sz
#        nbyte = 0xff
#        try nbyte = Base.peek(s) end
#        (nbyte == 0xff) && (return (state.eof = true))
#        if nbyte == b.block_delim
#            read(s)
#            return (state.eof = true)
#        end
#    end
#    false
#end
#
#function read(b::BlockStreamIO, x::Type{Uint8}) 
#    ret = read(b.b.source, x)
#    b.block_pos += 1
#    ret
#end
#
#position(b::BlockStreamIO) = b.block_pos
#
#