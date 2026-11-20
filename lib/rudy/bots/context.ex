# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.Bots.Context do
  @moduledoc """
  What a handler is given and returns: who is talking, the update, the
  conversation state, and the actions collected so far.
  """
  defstruct addon: nil,
            scope: nil,
            user: nil,
            update: nil,
            input: nil,
            lang: "en",
            step: nil,
            data: %{},
            capabilities: [],
            granted: [],
            hosts: [],
            operator: false,
            system: %{},
            actions: [],
            # On a server: the API context of the node running the handler, used by
            # the SDK's reads and effects; add-ons never use it directly. In tests:
            # what the harness answers those reads with (see Rudy.AddonSDK.Harness).
            runtime: nil,
            # How many effects this handler ran; with the input it names each one.
            effects: 0,
            state_version: 1,
            read_version: 0,
            written: false

  @type t :: %__MODULE__{}
end
