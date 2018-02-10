# This file is a part of Julia. License is MIT: https://julialang.org/license

@testset "ExponentialBackOff" begin
    @test length(ExponentialBackOff(n=10)) == 10
    @test collect(ExponentialBackOff(n=10, first_delay=0.01))[1] == 0.01
    @test maximum(ExponentialBackOff(n=10, max_delay=0.06)) == 0.06
    ratio(x) = x[2:end]./x[1:end-1]
    @test all(x->x ≈ 10.0, ratio(collect(ExponentialBackOff(n=10, max_delay=Inf, factor=10, jitter=0.0))))
    guardsrand(12345) do
        @test (mean(ratio(collect(ExponentialBackOff(n=100, max_delay=Inf, factor=1, jitter=0.1)))) - 1.0) < 1e-4
    end
end
@testset "retrying after errors" begin
    function foo_error(c, n)
        c[1] += 1
        if c[1] <= n
            error("foo")
        end
        return 7
    end

    # Success on first attempt
    c = [0]
    @test retry(foo_error)(c,0) == 7
    @test c[1] == 1

    # Success on second attempt
    c = [0]
    @test retry(foo_error)(c,1) == 7
    @test c[1] == 2

    # 2 failed retry attempts, so exception is raised
    c = [0]
    ex = try retry(foo_error, delays=ExponentialBackOff(n=2))(c,3) catch e; e end
    @test ex.msg == "foo"
    @test c[1] == 3

    c = [0]
    ex = try retry(foo_error, check=(s,e)->(s,isa(e, ErrorException)))(c,2) catch e; e end
    @test typeof(ex) == ErrorException
    @test ex.msg == "foo"
    @test c[1] == 2

    c = [0]
    ex = try retry(foo_error, check=(s,e)->(s,e.msg == "foo"))(c,2) catch e; e end
    @test typeof(ex) == ErrorException
    @test ex.msg == "foo"
    @test c[1] == 2

    # No retry if condition does not match
    c = [0]
    ex = try retry(foo_error, check=(s,e)->(s,e.msg == "bar"))(c,2) catch e; e end
    @test typeof(ex) == ErrorException
    @test ex.msg == "foo"
    @test c[1] == 1

    c = [0]
    ex = try retry(foo_error, check=(s,e)->(s,try e.http_status_code == "503" end != true))(c,2) catch e; e end
    @test typeof(ex) == ErrorException
    @test ex.msg == "foo"
    @test c[1] == 2

    c = [0]
    ex = try retry(foo_error, check=(s,e)->(s,isa(e,SystemError)))(c,2) catch e; e end
    @test typeof(ex) == ErrorException
    @test ex.msg == "foo"
    @test c[1] == 1

    # Functions with keyword arguments
    foo_kwargs(x; y=5) = x + y
    @test retry(foo_kwargs)(3) == 8
    @test retry(foo_kwargs)(3; y=4) == 7
end

macro catch_exception_object(code)
    quote
        err = try
            $(esc(code))
            nothing
        catch e
            e
        end
        if err == nothing
            error("Expected exception, got $err.")
        end
        err
    end
end

@testset "Chained comparisons" begin
    #6
    x=y=z = 1
    @test x == y == z
    @argcheck x == y == z
    z = 2
    @test_throws ArgumentError @argcheck x == y == z

    @test_throws ArgumentError @argcheck 1 ≈ 2 == 2
    @argcheck 1 == 1 ≈ 1 < 2 > 1.2
    @test_throws DimensionMismatch @argcheck 1 < 2 ==3 DimensionMismatch 
end

@testset "@argcheck" begin
    @test_throws ArgumentError @argcheck false
    @argcheck true

    x = 1
    @test_throws ArgumentError (@argcheck x > 1)
    @argcheck x>0 # does not throw

    n =2; m=3
    @test_throws DimensionMismatch (@argcheck n==m DimensionMismatch)
    @argcheck n==n DimensionMismatch

    denominator = 0
    @test_throws DivideError (@argcheck denominator != 0 DivideError())
    @argcheck 1 !=0 DivideError()
end

# exotic cases
struct MyError <: Exception
    msg::String
end
struct MyExoticError <: Exception
    a::Int
    b::Int
end

falsy(args...) = false
truthy(args...) = true

@testset "exotic cases" begin
    @argcheck truthy()
    @test_throws ArgumentError @argcheck falsy()

    @argcheck begin
        multi_line_true_is_no_problem = true
        multi_line_true_is_no_problem
    end
    @test_throws DimensionMismatch @argcheck let
        falsy(1,2)
    end DimensionMismatch

    op() = (x,y) -> x < y
    x = 1; y = 2
    @argcheck op()(x,y)
    @test_throws ArgumentError @argcheck op()(y,x)
    @test_throws ArgumentError @argcheck begin false end
    @test_throws DivideError @argcheck falsy() DivideError()
    err = @catch_exception_object @argcheck false MyExoticError(1,2)
    @test err === MyExoticError(1,2)
end

@testset "error message comparison" begin
    x = 1.23455475675
    y = 2.345345345
    # comparison
    err = @catch_exception_object @argcheck x == y MyError
    @test isa(err, MyError)
    msg = err.msg
    @test contains(msg, string(x))
    @test contains(msg, string(y))
    @test contains(msg, "x")
    @test contains(msg, "y")
    @test contains(msg, "==")

    x = 1.2
    y = 1.34
    z = -345.234
    err = @catch_exception_object @argcheck x < y < z
    msg = err.msg
    @test contains(msg, string(z))
    @test contains(msg, string(y))
    @test contains(msg, "y")
    @test contains(msg, "z")
    @test contains(msg, "<")
    @test !contains(msg, string(x))

    ≦(a,b) = false
    err = @catch_exception_object @argcheck x ≦ y ≦ z
    msg = err.msg
    @test contains(msg, "x")
    @test contains(msg, "y")
    @test contains(msg, string(x))
    @test contains(msg, string(y))
    @test contains(msg, "≦")
end

@testset "error message call" begin
    x = 1.2
    y = 1.34
    z = -345.234
    err = @catch_exception_object @argcheck falsy([x y; z z])
    msg = err.msg
    @test contains(msg, string(x))
    @test contains(msg, string(z))
    @test contains(msg, string(y))
    @test contains(msg, "y")
    @test contains(msg, "z")
    @test contains(msg, "x")
    @test contains(msg, "f")

    fail_function(args...) = false
    err = @catch_exception_object @argcheck fail_function(x,y,z) DimensionMismatch
    msg = err.msg

    @test err isa DimensionMismatch
    @test contains(msg, string(x))
    @test contains(msg, string(z))
    @test contains(msg, string(y))
    @test contains(msg, "y")
    @test contains(msg, "z")
    @test contains(msg, "x")
    @test contains(msg, "Got")
    @test contains(msg, "fail_function")

    err = @catch_exception_object @argcheck issorted([2,1])
    @test !contains(err.msg, "Got")
end

@testset "complicated calls" begin
    @argcheck issorted([2,1], rev=true)
    @argcheck issorted([2,1]; rev=true)
    xs = [[1,2]]
    @argcheck issorted(xs...)
end

@testset "custom message" begin
    x = 0
    @test_throws ArgumentError @argcheck x > 1 "this should not happen"
    @argcheck true "this should not happen"
end

@testset "@check" begin
    @check true
    E = ErrorException
    @test_throws E @check false
    @test_throws E @check false "oh no"
    @test_throws DimensionMismatch @check false DimensionMismatch
end
