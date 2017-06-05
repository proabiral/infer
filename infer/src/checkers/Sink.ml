(*
 * Copyright (c) 2016 - present Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *)

open! IStd

module F = Format
module L = Logging

module type Kind = sig
  include TraceElem.Kind

  (** return the parameter index and sink kind for the given call site with the given actuals *)
  val get : Typ.Procname.t -> HilExp.t list -> Tenv.t -> (t * int) list
end

module type S = sig
  include TraceElem.S

  type parameter =
    {
      sink : t;
      (** sink type of the parameter *)
      index : int;
      (** index of the parameter *)
    }

  (** return the parameter index and sink kind for the given call site with the given actuals *)
  val get : CallSite.t -> HilExp.t list -> Tenv.t -> parameter list
end

module Make (Kind : Kind) = struct
  module Kind = Kind

  type t =
    {
      kind : Kind.t;
      site : CallSite.t;
    } [@@deriving compare]

  type parameter =
    {
      sink : t;
      (** sink type of the parameter *)
      index : int;
      (** index of the parameter *)
    }

  let kind t =
    t.kind

  let call_site t =
    t.site

  let make kind site =
    { kind; site; }

  let make_sink_param sink index =
    { sink; index; }

  let get site actuals tenv =
    List.map
      ~f:(fun (kind, index) -> make_sink_param (make kind site) index)
      (Kind.get (CallSite.pname site) actuals tenv)

  let with_callsite t callee_site =
    { t with site = callee_site; }

  let pp fmt s =
    F.fprintf fmt "%a(%a)" Kind.pp s.kind CallSite.pp s.site

  module Set = PrettyPrintable.MakePPSet(struct
      type nonrec t = t
      let compare = compare
      let pp = pp
    end)
end