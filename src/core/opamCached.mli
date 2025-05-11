(**************************************************************************)
(*                                                                        *)
(*    Copyright 2012-2020 OCamlPro                                        *)
(*    Copyright 2012 INRIA                                                *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(** Argument type for the [Make] functor *)
module type ARG = sig
  type t
  val name: string
end

(** Module handling a simple marshalled cache for a given data structure. A
    magic number is added to validate the version of the cache. *)
module Make (X: ARG): sig

  type t = X.t

  (** Marshal and write the cache to disk *)
  val save: OpamFilename.t -> t -> unit

  val save_with_channel: OpamFilename.t -> t -> out_channel

  (** Load the cache if it exists and is valid and compatible with the current
     binary. Clear it otherwise. *)
  val load: OpamFilename.t -> t option

  val load_with_channel: OpamFilename.t -> (t * in_channel) option

  val remove: OpamFilename.t -> unit

end
