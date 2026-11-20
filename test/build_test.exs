# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.AddonSDK.BuildTest do
  use ExUnit.Case, async: false
  alias Rudy.AddonSDK.{Builder, Bundle, Signing}

  @root Path.expand("..", __DIR__)

  for example <- ~w(hello notes) do
    test "#{example} builds into a bundle a server accepts" do
      assert {:ok, bundle, manifest} =
               Builder.build(Path.join(@root, "examples/#{unquote(example)}"))

      assert manifest["module"] =~ ~r/\ARudy\.Addons\.\w+\.V\d+_\d+_\d+\z/
      assert {:ok, parsed} = Bundle.check(bundle)

      assert Map.keys(parsed.beams)
             |> Enum.all?(&String.starts_with?(&1, "ebin/Elixir." <> manifest["module"]))
    end
  end

  test "a beam calling outside the allowlist is refused at build time" do
    dir = Path.join(System.tmp_dir!(), "rudy-addon-bad-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib"))

    File.write!(
      Path.join(dir, "addon.json"),
      ~s({"name":"bad","version":"1.0.0","id":429991,"username":"BadBot","module":"Rudy.Addons.Bad","capabilities":[]})
    )

    File.write!(Path.join(dir, "lib/bad.ex"), """
    defmodule Rudy.Addons.Bad do
      use Rudy.Bots.Addon, id: 429_991, username: "BadBot"
      def handle_update(ctx, _), do: (File.read!("/etc/passwd"); ctx)
    end
    """)

    assert {:error, {_, {:forbidden_imports, ["File.read!/1"]}}} = Builder.build(dir)
  after
    :ok
  end

  test "signatures verify with the public key and nothing else" do
    keys = Signing.generate()
    other = Signing.generate()
    {:ok, bundle, _} = Builder.build(Path.join(@root, "examples/hello"))
    {:ok, signed} = Signing.sign_bundle(bundle, keys.private)

    assert {:ok, _} = Bundle.check(signed, [keys.public])
    assert {:error, :bad_signature} = Bundle.check(signed, [other.public])
    assert {:error, :unsigned} = Bundle.check(bundle, [keys.public])
    assert Signing.public_key(keys.private) == keys.public
  end

  test "a changed beam fails the hash check" do
    {:ok, bundle, _} = Builder.build(Path.join(@root, "examples/hello"))
    {:ok, parsed} = Bundle.parse(bundle)
    [{path, beam} | _] = Enum.to_list(parsed.beams)
    tampered = Bundle.pack(parsed.manifest_bytes, Map.put(parsed.beams, path, beam <> <<0>>))
    assert {:error, :bad_hash} = Bundle.check(tampered)
  end
end
