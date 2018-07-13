Base.__init__()

function create_precompile_file()
    println("Generating precompile statements...")
    t = time()

    sysimg = joinpath(dirname(Sys.BINDIR), "lib", "julia", "sys")
    tmp = tempname()
    if haskey(Base.loaded_modules, Base.PkgId(Base.UUID("3fa0cd96-eef1-5676-8a61-b3b8758bbffb"), "REPL"))
        setup = """
        @async while true
            sleep(0.01)
            if isdefined(Base, :active_repl)
                exit(0)
            end
        end
        """
        # Record precompile statements when starting a julia session with a repl
        run(pipeline(`$(Base.julia_cmd()) --sysimage $sysimg.ji --trace-compile=yes -O0 --banner=no --startup-file=no -e $setup -i`; stderr=tmp))

        # Replay a REPL script
        repl_replay = joinpath(@__DIR__, "precompile_replay.jl")
        if isfile(repl_replay)
            run(pipeline(`$(Base.julia_cmd()) --sysimage $sysimg.ji --trace-compile=yes -O0 --startup-file=no $repl_replay`; stderr=tmp, append=true))
        end
    else
        # No REPL, just record the startup
        run(pipeline(`$(Base.julia_cmd()) --sysimage $sysimg.ji --trace-compile=yes -O0 --startup-file=no -e0`; stderr=tmp))
    end

    isfile(tmp) || return

    # Replace the FakeTermiaal with a TTYYerminal and filter out everything we compiled in Main
    precompiles = readlines(tmp)
    new_precompiles = Set{String}()
    for statement in precompiles
        startswith(statement, "precompile(Tuple{") || continue
        statement = replace(statement, "FakeTerminals.FakeTerminal" => "REPL.Terminals.TTYTerminal")
        (occursin(r"Main.", statement) || occursin(r"FakeTerminals.", statement)) && continue
        push!(new_precompiles, statement)
    end

    write(tmp, join(sort(collect(new_precompiles)), '\n'))
    # Load the precompile statements
    let
        PrecompileStagingArea = Module()
        for (_pkgid, _mod) in Base.loaded_modules
            if !(_pkgid.name in ("Main", "Core", "Base"))
                @eval PrecompileStagingArea $(Symbol(_mod)) = $_mod
            end
        end

        Base.include(PrecompileStagingArea, tmp)
        @eval PrecompileStagingArea begin
            # Could startup with REPL banner instead but it is a bit visually noisy, so just precompile it here.
            precompile(Tuple{typeof(REPL.banner), REPL.Terminals.TTYTerminal, REPL.Terminals.TTYTerminal})
        end

    end

    print("Precompile statements generated in "), Base.time_print((time() - t) * 10^9)
    println()
    return
end

create_precompile_file()

