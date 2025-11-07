using Documenter
using Hedgehog

makedocs(
    sitename = "Hedgehog.jl",
    modules = [Hedgehog],
    format = Documenter.HTML(
        prettyurls = true,
        canonical = "https://aleCombi.github.io/Hedgehog.jl/stable/",
        assets = ["assets/favicon.ico"],
        # --- add one of the following ---
        size_threshold = 400 * 1024,        # hard error at ~400 KiB
        size_threshold_warn = 200 * 1024,   # warn above ~200 KiB
        # OR: size_threshold = nothing,     # disable hard limit entirely
    ),
    clean = true,
    checkdocs = :exports,
    pages = [
        "Home" => "index.md",
        "Pricing Methods" => "pricing_methods.md",
        "Greek Methods" => "greeks_doc.md",
        "Roadmap" => "derivatives_pricing_roadmap.md",
        "Interactive Examples" => "interactive.md",
        "API Reference" => "api.md",
    ],
)

deploydocs(
    repo = "github.com/aleCombi/Hedgehog.jl.git",
    devbranch = "master",
    target = "build",
    push_preview = true
)