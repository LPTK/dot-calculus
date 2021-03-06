
Set Implicit Arguments.

(* CoqIDE users: Run open.sh (in ./ln) to start coqide, then open this file. *)
Require Import LibLN.


(* ###################################################################### *)
(* ###################################################################### *)
(** * Definitions *)

(* ###################################################################### *)
(** ** Syntax *)

(** If it's clear whether a type, field or method is meant, we use nat, 
    if not, we use label: *)
Inductive label: Type :=
| label_typ: nat -> label
| label_fld: nat -> label
| label_mtd: nat -> label.

Inductive avar : Type :=
  | avar_b : nat -> avar  (* bound var (de Bruijn index) *)
  | avar_f : var -> avar. (* free var ("name"), refers to tenv or venv *)

Inductive pth : Type :=
  | pth_var : avar -> pth.

Inductive typ : Type :=
  | typ_top  : typ
  | typ_bot  : typ
  | typ_bind : decs -> typ (* { z => decs } *)
  | typ_sel : pth -> label -> typ (* p.L *)
with dec : Type :=
  | dec_typ  : typ -> typ -> dec
  | dec_fld  : typ -> dec
  | dec_mtd : typ -> typ -> dec
with decs : Type :=
  | decs_nil : decs
  | decs_cons : nat -> dec -> decs -> decs.

Inductive trm : Type :=
  | trm_var  : avar -> trm
  | trm_new  : typ -> defs -> trm
  | trm_sel  : trm -> nat -> trm
  | trm_call : trm -> nat -> trm -> trm
with def : Type :=
  | def_typ : def (* just a placeholder *)
  | def_fld : avar -> def (* cannot have term here, need to assign first *)
  | def_mtd : trm -> def (* one nameless argument *)
with defs : Type :=
  | defs_nil : defs
  | defs_cons : nat -> def -> defs -> defs.

Inductive obj : Type :=
  | object : typ -> defs -> obj. (* T { z => ds } *)

(** *** Typing environment ("Gamma") *)
Definition ctx := env typ.

(** *** Value environment ("store") *)
Definition sto := env obj.

(** *** Syntactic sugar *)
Definition trm_fun(T U: typ)(body: trm) := 
  trm_new (typ_bind (decs_cons 0 (dec_mtd T U)  decs_nil))
                    (defs_cons 0 (def_mtd body) defs_nil).
Definition trm_app(func arg: trm) := trm_call func 0 arg.
Definition trm_let(T U: typ)(rhs body: trm) := trm_app (trm_fun T U body) rhs.
Definition typ_arrow(T1 T2: typ) := typ_bind (decs_cons 0 (dec_mtd T1 T2) decs_nil).


(* ###################################################################### *)
(** ** Declaration and definition lists *)

Definition label_for_def(n: nat)(d: def): label := match d with
| def_typ     => label_typ n
| def_fld _   => label_fld n
| def_mtd _   => label_mtd n
end.
Definition label_for_dec(n: nat)(D: dec): label := match D with
| dec_typ _ _ => label_typ n
| dec_fld _   => label_fld n
| dec_mtd _ _ => label_mtd n
end.

Fixpoint get_def(l: label)(ds: defs): option def := match ds with
| defs_nil => None
| defs_cons n d ds' => If l = label_for_def n d then Some d else get_def l ds'
end.
Fixpoint get_dec(l: label)(Ds: decs): option dec := match Ds with
| decs_nil => None
| decs_cons n D Ds' => If l = label_for_dec n D then Some D else get_dec l Ds'
end.

Definition defs_has(ds: defs)(l: label)(d: def): Prop := (get_def l ds = Some d).
Definition decs_has(Ds: decs)(l: label)(D: dec): Prop := (get_dec l Ds = Some D).

Definition defs_hasnt(ds: defs)(l: label): Prop := (get_def l ds = None).
Definition decs_hasnt(Ds: decs)(l: label): Prop := (get_dec l Ds = None).


(* ###################################################################### *)
(** ** Opening *)

(** Opening replaces in some syntax a bound variable with dangling index (k) 
   by a free variable x. *)

Definition open_rec_avar (k: nat) (u: var) (a: avar) : avar :=
  match a with
  | avar_b i => If k = i then avar_f u else avar_b i
  | avar_f x => avar_f x
  end.

Definition open_rec_pth (k: nat) (u: var) (p: pth) : pth :=
  match p with
  | pth_var a => pth_var (open_rec_avar k u a)
  end.

Fixpoint open_rec_typ (k: nat) (u: var) (T: typ) { struct T } : typ :=
  match T with
  | typ_top     => typ_top
  | typ_bot     => typ_bot
  | typ_bind Ds => typ_bind (open_rec_decs (S k) u Ds)
  | typ_sel p L => typ_sel (open_rec_pth k u p) L
  end
with open_rec_dec (k: nat) (u: var) (D: dec) { struct D } : dec :=
  match D with
  | dec_typ T U => dec_typ (open_rec_typ k u T) (open_rec_typ k u U)
  | dec_fld T   => dec_fld (open_rec_typ k u T)
  | dec_mtd T U => dec_mtd (open_rec_typ k u T) (open_rec_typ k u U)
  end
with open_rec_decs (k: nat) (u: var) (Ds: decs) { struct Ds } : decs :=
  match Ds with
  | decs_nil          => decs_nil
  | decs_cons n D Ds' => decs_cons n (open_rec_dec k u D) (open_rec_decs k u Ds')
  end.

Fixpoint open_rec_trm (k: nat) (u: var) (t: trm) { struct t } : trm :=
  match t with
  | trm_var a      => trm_var (open_rec_avar k u a)
  | trm_new T ds   => trm_new (open_rec_typ k u T) (open_rec_defs (S k) u ds)
  | trm_sel e n    => trm_sel (open_rec_trm k u e) n
  | trm_call o m a => trm_call (open_rec_trm k u o) m (open_rec_trm k u a)
  end
with open_rec_def (k: nat) (u: var) (d: def) { struct d } : def :=
  match d with
  | def_typ   => def_typ
  | def_fld a => def_fld (open_rec_avar k u a)
  | def_mtd e => def_mtd (open_rec_trm (S k) u e)
  end
with open_rec_defs (k: nat) (u: var) (ds: defs) { struct ds } : defs :=
  match ds with
  | defs_nil => defs_nil
  | defs_cons n d tl => defs_cons n (open_rec_def k u d) (open_rec_defs k u tl)
  end.

Definition open_avar u a := open_rec_avar  0 u a.
Definition open_pth  u p := open_rec_pth   0 u p.
Definition open_typ  u t := open_rec_typ   0 u t.
Definition open_dec  u d := open_rec_dec   0 u d.
Definition open_decs u l := open_rec_decs  0 u l.
Definition open_trm  u e := open_rec_trm   0 u e.
Definition open_def  u d := open_rec_def   0 u d.
Definition open_defs u l := open_rec_defs  0 u l.


(* ###################################################################### *)
(** ** Free variables *)

Definition fv_avar (a: avar) : vars :=
  match a with
  | avar_b i => \{}
  | avar_f x => \{x}
  end.

Definition fv_pth (p: pth) : vars :=
  match p with
  | pth_var a => fv_avar a
  end.

Fixpoint fv_typ (T: typ) { struct T } : vars :=
  match T with
  | typ_top     => \{}
  | typ_bot     => \{}
  | typ_bind Ds => fv_decs Ds
  | typ_sel p L => fv_pth p
  end
with fv_dec (D: dec) { struct D } : vars :=
  match D with
  | dec_typ T U => (fv_typ T) \u (fv_typ U)
  | dec_fld T   => (fv_typ T)
  | dec_mtd T U => (fv_typ T) \u (fv_typ U)
  end
with fv_decs (Ds: decs) { struct Ds } : vars :=
  match Ds with
  | decs_nil          => \{}
  | decs_cons n D Ds' => (fv_dec D) \u (fv_decs Ds')
  end.

(* Since we define defs ourselves instead of using [list def], we don't have any
   termination proof problems: *)
Fixpoint fv_trm (t: trm) : vars :=
  match t with
  | trm_var x        => (fv_avar x)
  | trm_new T ds     => (fv_typ T) \u (fv_defs ds)
  | trm_sel t l      => (fv_trm t)
  | trm_call t1 m t2 => (fv_trm t1) \u (fv_trm t2)
  end
with fv_def (d: def) : vars :=
  match d with
  | def_typ   => \{}
  | def_fld x => fv_avar x
  | def_mtd u => fv_trm u
  end
with fv_defs(ds: defs) : vars :=
  match ds with
  | defs_nil         => \{}
  | defs_cons n d tl => (fv_def d) \u (fv_defs tl)
  end.


(* ###################################################################### *)
(** ** Operational Semantics *)

(** Note: Terms given by user are closed, so they only contain avar_b, no avar_f.
    Whenever we introduce a new avar_f (only happens in red_new), we choose one
    which is not in the store, so we never have name clashes. *)
Inductive red : trm -> sto -> trm -> sto -> Prop :=
  (* computation rules *)
  | red_call : forall s x y m T ds body,
      binds x (object T ds) s ->
      defs_has (open_defs x ds) (label_mtd m) (def_mtd body) ->
      red (trm_call (trm_var (avar_f x)) m (trm_var (avar_f y))) s
          (open_trm y body) s
  | red_sel : forall s x y l T ds,
      binds x (object T ds) s ->
      defs_has (open_defs x ds) (label_fld l) (def_fld y) ->
      red (trm_sel (trm_var (avar_f x)) l) s
          (trm_var y) s
  | red_new : forall s T ds x,
      x # s ->
      red (trm_new T ds) s
          (trm_var (avar_f x)) (s & x ~ (object T ds))
  (* congruence rules *)
  | red_call1 : forall s o m a s' o',
      red o s o' s' ->
      red (trm_call o  m a) s
          (trm_call o' m a) s'
  | red_call2 : forall s x m a s' a',
      red a s a' s' ->
      red (trm_call (trm_var (avar_f x)) m a ) s
          (trm_call (trm_var (avar_f x)) m a') s'
  | red_sel1 : forall s o l s' o',
      red o s o' s' ->
      red (trm_sel o  l) s
          (trm_sel o' l) s'.

(* ###################################################################### *)
(** ** Specification of declaration intersection (not yet used) *)

Module Type Decs.

(* Will be part of syntax: *)
Parameter t_and: typ -> typ -> typ.
Parameter t_or:  typ -> typ -> typ.

Parameter intersect: decs -> decs -> decs.

Axiom intersect_spec_1: forall l D Ds1 Ds2,
  decs_has    Ds1                l D ->
  decs_hasnt  Ds2                l   ->
  decs_has   (intersect Ds1 Ds2) l D .

Axiom intersect_spec_2: forall l D Ds1 Ds2,
  decs_hasnt Ds1                 l   ->
  decs_has   Ds2                 l D ->
  decs_has   (intersect Ds1 Ds2) l D.

Axiom intersect_spec_12_typ: forall n S1 T1 S2 T2 Ds1 Ds2,
  decs_has Ds1                 (label_typ n) (dec_typ S1 T1) ->
  decs_has Ds2                 (label_typ n) (dec_typ S2 T2) ->
  decs_has (intersect Ds1 Ds2) (label_typ n) (dec_typ (t_or S1 S2) (t_and T1 T2)).

Axiom intersect_spec_12_fld: forall n T1 T2 Ds1 Ds2,
  decs_has Ds1                 (label_fld n) (dec_fld T1) ->
  decs_has Ds2                 (label_fld n) (dec_fld T2) ->
  decs_has (intersect Ds1 Ds2) (label_fld n) (dec_fld (t_and T1 T2)).

Axiom intersect_spec_12_mtd: forall n S1 T1 S2 T2 Ds1 Ds2,
  decs_has Ds1                 (label_mtd n) (dec_mtd S1 T1) ->
  decs_has Ds2                 (label_mtd n) (dec_mtd S2 T2) ->
  decs_has (intersect Ds1 Ds2) (label_mtd n) (dec_mtd (t_or S1 S2) (t_and T1 T2)).

Axiom intersect_spec_hasnt: forall l Ds1 Ds2,
  decs_hasnt Ds1 l ->
  decs_hasnt Ds2 l ->
  decs_hasnt (intersect Ds1 Ds2) l.

End Decs.


(* ###################################################################### *)
(** ** Typing *)

(* The store is not an argument of the typing judgment because
   * it's only needed in typing_trm_var_s
   * we must allow types in Gamma to depend on values in the store, which seems complicated
   * how can we ensure that the store is well-formed? By requiring it in the "leaf"
     typing rules (those without typing assumptions)? Typing rules become unintuitive,
     and maybe to prove that store is wf, we need to prove what we're about to prove...
*)

(* mode = "is transitivity at top level accepted?" *)
Inductive mode : Type := notrans | oktrans.

(* expansion returns a set of decs without opening them *)
Inductive exp : ctx -> typ -> decs -> Prop :=
  | exp_top : forall G, 
      exp G typ_top decs_nil
(*| exp_bot : typ_bot has no expansion *)
  | exp_bind : forall G Ds,
      exp G (typ_bind Ds) Ds
  | exp_sel : forall G x L Lo Hi Ds,
      phas G x L (dec_typ Lo Hi) ->
      exp G Hi Ds ->
      exp G (typ_sel (pth_var (avar_f x)) L) Ds
with phas : ctx -> var -> label -> dec -> Prop :=
  | phas_var : forall G x T Ds l D,
      binds x T G ->
      exp G T Ds ->
      decs_has Ds l D ->
      phas G x l (open_dec x D).

Inductive subtyp : mode -> ctx -> typ -> typ -> Prop :=
  | subtyp_refl : forall G T,
      subtyp notrans G T T
  | subtyp_top : forall G T,
      subtyp notrans G T typ_top
  | subtyp_bot : forall G T,
      subtyp notrans G typ_bot T
  | subtyp_bind : forall L G Ds1 Ds2,
      (forall z, z \notin L -> 
         subdecs oktrans
                 (G & z ~ (typ_bind Ds1))
                 (open_decs z Ds1) 
                 (open_decs z Ds2)) ->
      subtyp notrans G (typ_bind Ds1) (typ_bind Ds2)
  | subtyp_sel_l : forall G x L S U T,
      phas G x L (dec_typ S U) ->
      subtyp oktrans G U T ->
      subtyp notrans G (typ_sel (pth_var (avar_f x)) L) T
  | subtyp_sel_r : forall G x L S U T,
      phas G x L (dec_typ S U) ->
      subtyp oktrans G S U -> (* <--- makes proofs a lot easier!! *)
      subtyp oktrans G T S ->
      subtyp notrans G T (typ_sel (pth_var (avar_f x)) L)
  | subtyp_mode : forall G T1 T2,
      subtyp notrans G T1 T2 ->
      subtyp oktrans G T1 T2
  | subtyp_trans : forall G T1 T2 T3,
      subtyp oktrans G T1 T2 ->
      subtyp oktrans G T2 T3 ->
      subtyp oktrans G T1 T3
with subdec : mode -> ctx -> dec -> dec -> Prop :=
  | subdec_refl : forall m G D,
      subdec m G D D
  | subdec_typ : forall m G Lo1 Hi1 Lo2 Hi2,
      (* only allow implementable decl *)
      subtyp m G Lo1 Hi1 ->
      subtyp m G Lo2 Hi2 ->
      (* lhs narrower range than rhs *)
      subtyp m G Lo2 Lo1 ->
      subtyp m G Hi1 Hi2 ->
      (* conclusion *)
      subdec m G (dec_typ Lo1 Hi1) (dec_typ Lo2 Hi2)
  | subdec_fld : forall m G T1 T2,
      subtyp m G T1 T2 ->
      subdec m G (dec_fld T1) (dec_fld T2)
  | subdec_mtd : forall m G S1 T1 S2 T2,
      subtyp m G S2 S1 ->
      subtyp m G T1 T2 ->
      subdec m G (dec_mtd S1 T1) (dec_mtd S2 T2)
with subdecs : mode -> ctx -> decs -> decs -> Prop :=
  | subdecs_empty : forall m G Ds,
      subdecs m G Ds decs_nil
  | subdecs_push : forall m G n Ds1 Ds2 D1 D2,
      decs_has   Ds1 (label_for_dec n D2) D1 ->
      (* decs_hasnt Ds2 (label_for_dec n D2) -> (* we don't accept duplicates in rhs *)*)
      subdec m G D1 D2 ->
      subdecs m G Ds1 Ds2 ->
      subdecs m G Ds1 (decs_cons n D2 Ds2).

Inductive has : ctx -> trm -> label -> dec -> Prop :=
  | has_trm : forall G t T Ds l D,
      ty_trm G t T ->
      exp G T Ds ->
      decs_has Ds l D ->
      (forall z, (open_dec z D) = D) ->
      has G t l D
  | has_var : forall G v T Ds l D,
      ty_trm G (trm_var (avar_f v)) T ->
      exp G T Ds ->
      decs_has Ds l D ->
      has G (trm_var (avar_f v)) l (open_dec v D)
with ty_trm : ctx -> trm -> typ -> Prop :=
  | ty_var : forall G x T,
      binds x T G ->
      ty_trm G (trm_var (avar_f x)) T
  | ty_sel : forall G t l T,
      has G t (label_fld l) (dec_fld T) ->
      ty_trm G (trm_sel t l) T
  | ty_call : forall G t m U V u,
      has G t (label_mtd m) (dec_mtd U V) ->
      ty_trm G u U ->
      ty_trm G (trm_call t m u) V
  | ty_new : forall L G T ds Ds,
      exp G T Ds ->
      (forall x, x \notin L ->
                 ty_defs (G & x ~ T) (open_defs x ds) (open_decs x Ds)) ->
      (forall x, x \notin L ->
                 forall M S U, decs_has (open_decs x Ds) M (dec_typ S U) -> 
                               subtyp oktrans (G & x ~ T) S U) ->
      ty_trm G (trm_new T ds) T
  | ty_sbsm : forall G t T U,
      ty_trm G t T ->
      subtyp oktrans G T U ->
      ty_trm G t U
with ty_def : ctx -> def -> dec -> Prop :=
  | ty_typ : forall G S T,
      ty_def G def_typ (dec_typ S T)
  | ty_fld : forall G v T,
      ty_trm G (trm_var v) T ->
      ty_def G (def_fld v) (dec_fld T)
  | ty_mtd : forall L G S T t,
      (forall x, x \notin L -> ty_trm (G & x ~ S) (open_trm x t) T) ->
      ty_def G (def_mtd t) (dec_mtd S T)
with ty_defs : ctx -> defs -> decs -> Prop :=
  | ty_dsnil : forall G,
      ty_defs G defs_nil decs_nil
  | ty_dscons : forall G ds d Ds D n,
      ty_defs G ds Ds ->
      ty_def  G d D ->
      ty_defs G (defs_cons n d ds) (decs_cons n D Ds).


(** *** Well-formed store *)
Inductive wf_sto: sto -> ctx -> Prop :=
  | wf_sto_empty : wf_sto empty empty
  | wf_sto_push : forall s G x T ds Ds,
      wf_sto s G ->
      x # s ->
      x # G ->
      (* What's below is the same as the ty_new rule, but we don't use ty_trm,
         because it could be subsumption *)
      exp G T Ds ->
      ty_defs (G & x ~ T) (open_defs x ds) (open_decs x Ds) ->
      (forall L S U, decs_has (open_decs x Ds) L (dec_typ S U) -> 
                     subtyp notrans (G & x ~ T) S U) ->
      (*
      (forall x, x \notin L ->
                 ty_defs (G & x ~ T) (open_defs x ds) (open_decs x Ds) /\
                 forall M S U, decs_has (open_decs x Ds) M (dec_typ S U) -> 
                               subtyp notrans (G & x ~ T) S U) ->
      *)
      wf_sto (s & x ~ (object T ds)) (G & x ~ T).

(*
ty_trm_new does not check for good bounds recursively inside the types, but that's
not a problem because when creating an object x which has (L: S..U), we have two cases:
Case 1: The object x has a field x.f = y of type x.L: Then y has a type
        Y <: x.L, and when checking the creation of y, we checked that
        the type members of Y are good, so the those of S and U are good as well,
        because S and U are supertypes of Y.
Case 2: The object x has no field of type x.L: Then we can only refer to the
        type x.L, but not to possibly bad type members of the type x.L.
*)

(* ###################################################################### *)
(** ** Statements we want to prove *)

Definition progress := forall s G e T,
  wf_sto s G ->
  ty_trm G e T -> 
  (
    (* can step *)
    (exists e' s', red e s e' s') \/
    (* or is a value *)
    (exists x o, e = (trm_var (avar_f x)) /\ binds x o s)
  ).

Definition preservation := forall s G e T e' s',
  wf_sto s G -> ty_trm G e T -> red e s e' s' ->
  (exists G', wf_sto s' G' /\ ty_trm G' e' T).


(* ###################################################################### *)
(* ###################################################################### *)
(** * Infrastructure *)


Inductive notsel: typ -> Prop :=
  | notsel_top  : notsel typ_top
  | notsel_bot  : notsel typ_bot
  | notsel_bind : forall Ds, notsel (typ_bind Ds).


(* ###################################################################### *)
(** ** Induction principles *)

Scheme trm_mut  := Induction for trm  Sort Prop
with   def_mut  := Induction for def  Sort Prop
with   defs_mut := Induction for defs Sort Prop.
Combined Scheme trm_mutind from trm_mut, def_mut, defs_mut.

Scheme typ_mut  := Induction for typ  Sort Prop
with   dec_mut  := Induction for dec  Sort Prop
with   decs_mut := Induction for decs Sort Prop.
Combined Scheme typ_mutind from typ_mut, dec_mut, decs_mut.

Scheme exp_mut     := Induction for exp     Sort Prop
with   phas_mut := Induction for phas Sort Prop.
Combined Scheme exp_phas_mutind from exp_mut, phas_mut.

Scheme subtyp_mut  := Induction for subtyp  Sort Prop
with   subdec_mut  := Induction for subdec  Sort Prop
with   subdecs_mut := Induction for subdecs Sort Prop.
Combined Scheme subtyp_mutind from subtyp_mut, subdec_mut, subdecs_mut.

Scheme has_mut := Induction for has Sort Prop
with   ty_trm_mut  := Induction for ty_trm  Sort Prop
with   ty_def_mut  := Induction for ty_def  Sort Prop
with   ty_defs_mut := Induction for ty_defs Sort Prop.
Combined Scheme ty_mutind from has_mut, ty_trm_mut, ty_def_mut, ty_defs_mut.

Scheme has_mut2 := Induction for has Sort Prop
with   ty_trm_mut2  := Induction for ty_trm  Sort Prop.
Combined Scheme ty_has_mutind from has_mut2, ty_trm_mut2.


(* ###################################################################### *)
(** ** Tactics *)

Ltac auto_specialize :=
  repeat match goal with
  | Impl: ?Cond ->            _ |- _ => let HC := fresh in 
      assert (HC: Cond) by auto; specialize (Impl HC); clear HC
  | Impl: forall (_ : ?Cond), _ |- _ => match goal with
      | p: Cond |- _ => specialize (Impl p)
      end
  end.

Ltac gather_vars :=
  let A := gather_vars_with (fun x : vars      => x         ) in
  let B := gather_vars_with (fun x : var       => \{ x }    ) in
  let C := gather_vars_with (fun x : ctx       => dom x     ) in
  let D := gather_vars_with (fun x : sto       => dom x     ) in
  let E := gather_vars_with (fun x : avar      => fv_avar  x) in
  let F := gather_vars_with (fun x : trm       => fv_trm   x) in
  let G := gather_vars_with (fun x : def       => fv_def   x) in
  let H := gather_vars_with (fun x : defs      => fv_defs  x) in
  let I := gather_vars_with (fun x : typ       => fv_typ   x) in
  let J := gather_vars_with (fun x : dec       => fv_dec   x) in
  let K := gather_vars_with (fun x : decs      => fv_decs  x) in
  constr:(A \u B \u C \u D \u E \u F \u G \u H \u I \u J \u K).

Ltac pick_fresh x :=
  let L := gather_vars in (pick_fresh_gen L x).

Tactic Notation "apply_fresh" constr(T) "as" ident(x) :=
  apply_fresh_base T gather_vars x.

Hint Constructors subtyp.
Hint Constructors subdec.
Hint Constructors notsel.


(* ###################################################################### *)
(** ** Realizability *)

Definition real(G: ctx): Prop := exists s, wf_sto s G.


(* ###################################################################### *)
(** ** Definition of var-by-var substitution *)

(** Note that substitution is not part of the definitions, because for the
    definitions, opening is sufficient. For the proofs, however, we also
    need substitution, but only var-by-var substitution, not var-by-term
    substitution. That's why we don't need a judgment asserting that a term
    is locally closed. *)

Fixpoint subst_avar (z: var) (u: var) (a: avar) { struct a } : avar :=
  match a with
  | avar_b i => avar_b i
  | avar_f x => If x = z then (avar_f u) else (avar_f x)
  end.

Definition subst_pth (z: var) (u: var) (p: pth) : pth :=
  match p with
  | pth_var a => pth_var (subst_avar z u a)
  end.

Fixpoint subst_typ (z: var) (u: var) (T: typ) { struct T } : typ :=
  match T with
  | typ_top     => typ_top
  | typ_bot     => typ_bot
  | typ_bind Ds => typ_bind (subst_decs z u Ds)
  | typ_sel p L => typ_sel (subst_pth z u p) L
  end
with subst_dec (z: var) (u: var) (D: dec) { struct D } : dec :=
  match D with
  | dec_typ T U => dec_typ (subst_typ z u T) (subst_typ z u U)
  | dec_fld T   => dec_fld (subst_typ z u T)
  | dec_mtd T U => dec_mtd (subst_typ z u T) (subst_typ z u U)
  end
with subst_decs (z: var) (u: var) (Ds: decs) { struct Ds } : decs :=
  match Ds with
  | decs_nil          => decs_nil
  | decs_cons n D Ds' => decs_cons n (subst_dec z u D) (subst_decs z u Ds')
  end.

Fixpoint subst_trm (z: var) (u: var) (t: trm) : trm :=
  match t with
  | trm_var x        => trm_var (subst_avar z u x)
  | trm_new T ds     => trm_new (subst_typ z u T) (subst_defs z u ds)
  | trm_sel t l      => trm_sel (subst_trm z u t) l
  | trm_call t1 m t2 => trm_call (subst_trm z u t1) m (subst_trm z u t2)
  end
with subst_def (z: var) (u: var) (d: def) : def :=
  match d with
  | def_typ => def_typ
  | def_fld x => def_fld (subst_avar z u x)
  | def_mtd b => def_mtd (subst_trm z u b)
  end
with subst_defs (z: var) (u: var) (ds: defs) : defs :=
  match ds with
  | defs_nil => defs_nil
  | defs_cons n d rest => defs_cons n (subst_def z u d) (subst_defs z u rest)
  end.

Definition subst_ctx (z: var) (u: var) (G: ctx) : ctx := map (subst_typ z u) G.


(* ###################################################################### *)
(** ** Lemmas for var-by-var substitution *)

Lemma subst_fresh_avar: forall x y,
  (forall a: avar, x \notin fv_avar a -> subst_avar x y a = a).
Proof.
  intros. destruct* a. simpl. case_var*. simpls. notin_false.
Qed.

Lemma subst_fresh_pth: forall x y,
  (forall p: pth, x \notin fv_pth p -> subst_pth x y p = p).
Proof.
  intros. destruct p. simpl. f_equal. apply* subst_fresh_avar.
Qed.

Lemma subst_fresh_typ_dec_decs: forall x y,
  (forall T : typ , x \notin fv_typ  T  -> subst_typ  x y T  = T ) /\
  (forall d : dec , x \notin fv_dec  d  -> subst_dec  x y d  = d ) /\
  (forall ds: decs, x \notin fv_decs ds -> subst_decs x y ds = ds).
Proof.
  intros x y. apply typ_mutind; intros; simpls; f_equal*. apply* subst_fresh_pth.
Qed.

Lemma subst_fresh_trm_def_defs: forall x y,
  (forall t : trm , x \notin fv_trm  t  -> subst_trm  x y t  = t ) /\
  (forall d : def , x \notin fv_def  d  -> subst_def  x y d  = d ) /\
  (forall ds: defs, x \notin fv_defs ds -> subst_defs x y ds = ds).
Proof.
  intros x y. apply trm_mutind; intros; simpls; f_equal*.
  + apply* subst_fresh_avar.
  + apply* subst_fresh_typ_dec_decs.
  + apply* subst_fresh_avar.
Qed.

Definition subst_fvar(x y z: var): var := If x = z then y else z.

Lemma subst_open_commute_avar: forall x y u,
  (forall a: avar, forall n: nat,
    subst_avar x y (open_rec_avar n u a) 
    = open_rec_avar n (subst_fvar x y u) (subst_avar  x y a)).
Proof.
  intros. unfold subst_fvar, subst_avar, open_avar, open_rec_avar. destruct a.
  + repeat case_if; auto.
  + case_var*.
Qed.

Lemma subst_open_commute_pth: forall x y u,
  (forall p: pth, forall n: nat,
    subst_pth x y (open_rec_pth n u p) 
    = open_rec_pth n (subst_fvar x y u) (subst_pth x y p)).
Proof.
  intros. unfold subst_pth, open_pth, open_rec_pth. destruct p.
  f_equal. apply subst_open_commute_avar.
Qed.

(* "open and then substitute" = "substitute and then open" *)
Lemma subst_open_commute_typ_dec_decs: forall x y u,
  (forall t : typ, forall n: nat,
     subst_typ x y (open_rec_typ n u t)
     = open_rec_typ n (subst_fvar x y u) (subst_typ x y t)) /\
  (forall d : dec , forall n: nat, 
     subst_dec x y (open_rec_dec n u d)
     = open_rec_dec n (subst_fvar x y u) (subst_dec x y d)) /\
  (forall ds: decs, forall n: nat, 
     subst_decs x y (open_rec_decs n u ds)
     = open_rec_decs n (subst_fvar x y u) (subst_decs x y ds)).
Proof.
  intros. apply typ_mutind; intros; simpl; f_equal*. apply subst_open_commute_pth.
Qed.

(* "open and then substitute" = "substitute and then open" *)
Lemma subst_open_commute_trm_def_defs: forall x y u,
  (forall t : trm, forall n: nat,
     subst_trm x y (open_rec_trm n u t)
     = open_rec_trm n (subst_fvar x y u) (subst_trm x y t)) /\
  (forall d : def , forall n: nat, 
     subst_def x y (open_rec_def n u d)
     = open_rec_def n (subst_fvar x y u) (subst_def x y d)) /\
  (forall ds: defs, forall n: nat, 
     subst_defs x y (open_rec_defs n u ds)
     = open_rec_defs n (subst_fvar x y u) (subst_defs x y ds)).
Proof.
  intros. apply trm_mutind; intros; simpl; f_equal*.
  + apply* subst_open_commute_avar.
  + apply* subst_open_commute_typ_dec_decs.
  + apply* subst_open_commute_avar.
Qed.

Lemma subst_open_commute_trm: forall x y u t,
  subst_trm x y (open_trm u t) = open_trm (subst_fvar x y u) (subst_trm x y t).
Proof.
  intros. apply* subst_open_commute_trm_def_defs.
Qed.

Lemma subst_open_commute_defs: forall x y u ds,
  subst_defs x y (open_defs u ds) = open_defs (subst_fvar x y u) (subst_defs x y ds).
Proof.
  intros. apply* subst_open_commute_trm_def_defs.
Qed.

Lemma subst_open_commute_typ: forall x y u T,
  subst_typ x y (open_typ u T) = open_typ (subst_fvar x y u) (subst_typ x y T).
Proof.
  intros. apply* subst_open_commute_typ_dec_decs.
Qed.

Lemma subst_open_commute_dec: forall x y u D,
  subst_dec x y (open_dec u D) = open_dec (subst_fvar x y u) (subst_dec x y D).
Proof.
  intros. apply* subst_open_commute_typ_dec_decs.
Qed.

Lemma subst_open_commute_decs: forall x y u Ds,
  subst_decs x y (open_decs u Ds) = open_decs (subst_fvar x y u) (subst_decs x y Ds).
Proof.
  intros. apply* subst_open_commute_typ_dec_decs.
Qed.

(* "Introduce a substitution after open": Opening a term t with a var u is the
   same as opening t with x and then replacing x by u. *)
Lemma subst_intro_trm: forall x u t, x \notin (fv_trm t) ->
  open_trm u t = subst_trm x u (open_trm x t).
Proof.
  introv Fr. unfold open_trm. rewrite* subst_open_commute_trm.
  destruct (@subst_fresh_trm_def_defs x u) as [Q _]. rewrite* (Q t).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_intro_defs: forall x u ds, x \notin (fv_defs ds) ->
  open_defs u ds = subst_defs x u (open_defs x ds).
Proof.
  introv Fr. unfold open_trm. rewrite* subst_open_commute_defs.
  destruct (@subst_fresh_trm_def_defs x u) as [_ [_ Q]]. rewrite* (Q ds).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_intro_typ: forall x u T, x \notin (fv_typ T) ->
  open_typ u T = subst_typ x u (open_typ x T).
Proof.
  introv Fr. unfold open_typ. rewrite* subst_open_commute_typ.
  destruct (@subst_fresh_typ_dec_decs x u) as [Q _]. rewrite* (Q T).
  unfold subst_fvar. case_var*.
Qed.

Lemma subst_intro_decs: forall x u Ds, x \notin (fv_decs Ds) ->
  open_decs u Ds = subst_decs x u (open_decs x Ds).
Proof.
  introv Fr. unfold open_trm. rewrite* subst_open_commute_decs.
  destruct (@subst_fresh_typ_dec_decs x u) as [_ [_ Q]]. rewrite* (Q Ds).
  unfold subst_fvar. case_var*.
Qed.

(* ###################################################################### *)
(** ** Helper lemmas for definition/declaration lists *)

Lemma defs_has_fld_sync: forall n d ds,
  defs_has ds (label_fld n) d -> exists x, d = (def_fld x).
Proof.
  introv Hhas. induction ds; unfolds defs_has, get_def. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_def in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma defs_has_mtd_sync: forall n d ds,
  defs_has ds (label_mtd n) d -> exists e, d = (def_mtd e).
Proof.
  introv Hhas. induction ds; unfolds defs_has, get_def. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_def in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma decs_has_fld_sync: forall n d ds,
  decs_has ds (label_fld n) d -> exists x, d = (dec_fld x).
Proof.
  introv Hhas. induction ds; unfolds decs_has, get_dec. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_dec in H. destruct* d; discriminate.
    - apply* IHds.
Qed.

Lemma decs_has_mtd_sync: forall n d ds,
  decs_has ds (label_mtd n) d -> exists T U, d = (dec_mtd T U).
Proof.
  introv Hhas. induction ds; unfolds decs_has, get_dec. 
  + discriminate.
  + case_if.
    - inversions Hhas. unfold label_for_dec in H. destruct* d; discriminate.
    - apply* IHds.
Qed.


(* ###################################################################### *)
(** ** Implementation of declaration intersection *)

(* Exercise: Give any implementation of `intersect`, and prove that it satisfies
   the specification. Happy hacking! ;-) *)
Module DecsImpl : Decs.

(* Will be part of syntax: *)
Parameter t_and: typ -> typ -> typ.
Parameter t_or:  typ -> typ -> typ.

Fixpoint refine_dec(n1: nat)(D1: dec)(Ds2: decs): dec := match Ds2 with
| decs_nil => D1
| decs_cons n2 D2 tail2 => match D1, D2 with
    | dec_typ T1 S1, dec_typ T2 S2 => If n1 = n2
                                      then dec_typ (t_or T1 T2) (t_and S1 S2) 
                                      else refine_dec n1 D1 tail2
    | dec_fld T1   , dec_fld T2    => If n1 = n2
                                      then dec_fld (t_and T1 T2) 
                                      else refine_dec n1 D1 tail2
    | dec_mtd T1 S1, dec_mtd T2 S2 => If n1 = n2
                                      then dec_mtd (t_or T1 T2) (t_and S1 S2) 
                                      else refine_dec n1 D1 tail2
    | _, _ => refine_dec n1 D1 tail2
    end
end.

Lemma refine_dec_spec_typ: forall Ds2 n T1 S1 T2 S2,
  decs_has Ds2 (label_typ n) (dec_typ T2 S2) ->
  refine_dec n (dec_typ T1 S1) Ds2 = dec_typ (t_or T1 T2) (t_and S1 S2).
Proof. 
  intro Ds2. induction Ds2; intros.
  + inversion H.
  + unfold decs_has, get_dec in H. case_if; fold get_dec in H.
    - inversions H. unfold label_for_dec in H0. inversions H0. simpl. case_if. reflexivity.
    - simpl. destruct d.
      * simpl in H0. case_if.
        apply IHDs2. unfold decs_has. assumption.
      * apply IHDs2. unfold decs_has. assumption.
      * apply IHDs2. unfold decs_has. assumption.
Qed.

Lemma refine_dec_spec_fld: forall Ds2 n T1 T2,
  decs_has Ds2 (label_fld n) (dec_fld T2) ->
  refine_dec n (dec_fld T1) Ds2 = dec_fld (t_and T1 T2).
Proof.
  intro Ds2. induction Ds2; intros.
  + inversion H.
  + unfold decs_has, get_dec in H. case_if; fold get_dec in H.
    - inversions H. unfold label_for_dec in H0. inversions H0. simpl. case_if. reflexivity.
    - simpl. destruct d.
      * apply IHDs2. unfold decs_has. assumption.
      * simpl in H0. case_if.
        apply IHDs2. unfold decs_has. assumption.
      * apply IHDs2. unfold decs_has. assumption.
Qed.

Lemma refine_dec_spec_mtd: forall Ds2 n T1 S1 T2 S2,
  decs_has Ds2 (label_mtd n) (dec_mtd T2 S2) ->
  refine_dec n (dec_mtd T1 S1) Ds2 = dec_mtd (t_or T1 T2) (t_and S1 S2).
Proof. 
  intro Ds2. induction Ds2; intros.
  + inversion H.
  + unfold decs_has, get_dec in H. case_if; fold get_dec in H.
    - inversions H. unfold label_for_dec in H0. inversions H0. simpl. case_if. reflexivity.
    - simpl. destruct d.
      * apply IHDs2. unfold decs_has. assumption.
      * apply IHDs2. unfold decs_has. assumption.
      * simpl in H0. case_if.
        apply IHDs2. unfold decs_has. assumption.
Qed.

Lemma refine_dec_spec_unbound: forall n D1 Ds2, 
  decs_hasnt Ds2 (label_for_dec n D1) ->
  refine_dec n D1 Ds2 = D1.
Proof. 
  intros. induction Ds2.
  + reflexivity.
  + unfold decs_hasnt, get_dec in H. fold get_dec in H. case_if. destruct D1.
    - destruct d; simpl in H0; unfold refine_dec.
      * case_if. fold refine_dec. apply IHDs2. assumption.
      * fold refine_dec. apply IHDs2. assumption.
      * fold refine_dec. apply IHDs2. assumption.
    - destruct d; simpl in H0; unfold refine_dec.
      * fold refine_dec. apply IHDs2. assumption.
      * case_if. fold refine_dec. apply IHDs2. assumption.
      * fold refine_dec. apply IHDs2. assumption.
    - destruct d; simpl in H0; unfold refine_dec.
      * fold refine_dec. apply IHDs2. assumption.
      * fold refine_dec. apply IHDs2. assumption.
      * case_if. fold refine_dec. apply IHDs2. assumption.
Qed.

Lemma refine_dec_preserves_label: forall n D1 Ds2,
  label_for_dec n (refine_dec n D1 Ds2) = label_for_dec n D1.
Proof.
  intros. induction Ds2.
  + reflexivity.
  + destruct D1; destruct d; unfold refine_dec in *; fold refine_dec in *; 
    solve [ assumption | case_if* ].
Qed.

Fixpoint refine_decs(Ds1: decs)(Ds2: decs): decs := match Ds1 with
| decs_nil => decs_nil
| decs_cons n D1 Ds1tail => decs_cons n (refine_dec n D1 Ds2) (refine_decs Ds1tail Ds2)
end.

Lemma refine_decs_spec_unbound: forall l D Ds1 Ds2,
  decs_has    Ds1                  l D ->
  decs_hasnt  Ds2                  l   ->
  decs_has   (refine_decs Ds1 Ds2) l D .
Proof.
  intros l D Ds1 Ds2. induction Ds1; introv Has Hasnt.
  + inversion Has.
  + unfold refine_decs; fold refine_decs. rename d into D'. unfold decs_has, get_dec.
    rewrite refine_dec_preserves_label. case_if.
    - unfold decs_has, get_dec in Has. case_if.
      inversions Has. f_equal. apply refine_dec_spec_unbound. assumption.
    - fold get_dec. unfold decs_has in *. unfold get_dec in Has. case_if.
      fold get_dec in Has. apply* IHDs1. 
Qed.

Lemma refine_decs_spec_unbound_preserved: forall l Ds1 Ds2,
  decs_hasnt Ds1                   l ->
  decs_hasnt (refine_decs Ds1 Ds2) l .
Proof. 
  introv Hasnt. induction Ds1.
  + simpl. assumption.
  + unfold refine_decs; fold refine_decs. rename d into D'. unfold decs_hasnt, get_dec.
    rewrite refine_dec_preserves_label. case_if.
    - unfold decs_hasnt, get_dec in Hasnt. case_if. (* contradiction *)
    - fold get_dec. unfold decs_has in *. apply IHDs1.
      unfold decs_hasnt, get_dec in Hasnt. case_if. fold get_dec in Hasnt. apply Hasnt.
Qed.

Lemma refine_decs_spec_typ: forall n Ds1 Ds2 T1 S1 T2 S2,
  decs_has  Ds1                  (label_typ n) (dec_typ T1 S1) ->
  decs_has  Ds2                  (label_typ n) (dec_typ T2 S2) ->
  decs_has (refine_decs Ds1 Ds2) (label_typ n) (dec_typ (t_or T1 T2) (t_and S1 S2)).
Proof.
  introv Has1 Has2. induction Ds1.
  + inversion Has1.
  + unfold decs_has, get_dec in Has1. case_if.
    - inversions Has1. simpl in H. inversions H. simpl. 
      rewrite (refine_dec_spec_typ _ _ Has2). unfold decs_has, get_dec. simpl.
      case_if. reflexivity.
    - fold get_dec in Has1. simpl. unfold decs_has, get_dec.
      rewrite refine_dec_preserves_label. case_if. fold get_dec.
      unfold decs_has in IHDs1. apply IHDs1. assumption.
Qed.

Lemma refine_decs_spec_fld: forall n Ds1 Ds2 T1 T2,
  decs_has  Ds1                  (label_fld n) (dec_fld T1) ->
  decs_has  Ds2                  (label_fld n) (dec_fld T2) ->
  decs_has (refine_decs Ds1 Ds2) (label_fld n) (dec_fld (t_and T1 T2)).
Proof. 
  introv Has1 Has2. induction Ds1.
  + inversion Has1.
  + unfold decs_has, get_dec in Has1. case_if.
    - inversions Has1. simpl in H. inversions H. simpl. 
      rewrite (refine_dec_spec_fld _ Has2). unfold decs_has, get_dec. simpl.
      case_if. reflexivity.
    - fold get_dec in Has1. simpl. unfold decs_has, get_dec.
      rewrite refine_dec_preserves_label. case_if. fold get_dec.
      unfold decs_has in IHDs1. apply IHDs1. assumption.
Qed.

Lemma refine_decs_spec_mtd: forall n Ds1 Ds2 T1 S1 T2 S2,
  decs_has  Ds1                  (label_mtd n) (dec_mtd T1 S1) ->
  decs_has  Ds2                  (label_mtd n) (dec_mtd T2 S2) ->
  decs_has (refine_decs Ds1 Ds2) (label_mtd n) (dec_mtd (t_or T1 T2) (t_and S1 S2)).
Proof.
  introv Has1 Has2. induction Ds1.
  + inversion Has1.
  + unfold decs_has, get_dec in Has1. case_if.
    - inversions Has1. simpl in H. inversions H. simpl. 
      rewrite (refine_dec_spec_mtd _ _ Has2). unfold decs_has, get_dec. simpl.
      case_if. reflexivity.
    - fold get_dec in Has1. simpl. unfold decs_has, get_dec.
      rewrite refine_dec_preserves_label. case_if. fold get_dec.
      unfold decs_has in IHDs1. apply IHDs1. assumption.
Qed.

Fixpoint decs_concat(Ds1 Ds2: decs) {struct Ds1}: decs := match Ds1 with
| decs_nil => Ds2
| decs_cons n D1 Ds1tail => decs_cons n D1 (decs_concat Ds1tail Ds2)
end.

(* Refined decs shadow the outdated decs of Ds2. *)
Definition intersect(Ds1 Ds2: decs): decs := decs_concat (refine_decs Ds1 Ds2) Ds2.

Lemma decs_has_concat_left : forall l D Ds1 Ds2,
  decs_has Ds1 l D ->
  decs_has (decs_concat Ds1 Ds2) l D.
Proof.
  introv Has. induction Ds1.
  + inversion Has.
  + simpl. unfold decs_has, get_dec in *. fold get_dec in *. case_if.
    - assumption.
    - apply IHDs1. assumption.
Qed. 

Lemma decs_has_concat_right : forall l D Ds1 Ds2,
  decs_hasnt Ds1 l ->
  decs_has Ds2 l D ->
  decs_has (decs_concat Ds1 Ds2) l D.
Proof.
  introv Hasnt Has. induction Ds1.
  + simpl. assumption.
  + simpl. unfold decs_has, get_dec. case_if.
    - unfold decs_hasnt, get_dec in Hasnt. case_if. (* contradiction *)
    - fold get_dec. apply IHDs1. unfold decs_hasnt, get_dec in Hasnt. case_if.
      apply Hasnt.
Qed.

Lemma decs_hasnt_concat : forall l Ds1 Ds2,
  decs_hasnt Ds1 l ->
  decs_hasnt Ds2 l ->
  decs_hasnt (decs_concat Ds1 Ds2) l.
Proof.
  introv Hasnt1 Hasnt2. induction Ds1.
  + simpl. assumption.
  + simpl. unfold decs_hasnt, get_dec. case_if.
    - unfold decs_hasnt, get_dec in Hasnt1. case_if. (* contradiction *)
    - fold get_dec. apply IHDs1. unfold decs_hasnt, get_dec in Hasnt1. case_if.
      apply Hasnt1.
Qed.

Lemma intersect_spec_1: forall l D Ds1 Ds2,
  decs_has    Ds1                l D ->
  decs_hasnt  Ds2                l   ->
  decs_has   (intersect Ds1 Ds2) l D .
Proof.
  intros. unfold intersect. apply decs_has_concat_left.
  apply refine_decs_spec_unbound; assumption.
Qed.

Lemma intersect_spec_2: forall l D Ds1 Ds2,
  decs_hasnt Ds1                 l   ->
  decs_has   Ds2                 l D ->
  decs_has   (intersect Ds1 Ds2) l D.
Proof.
  introv Hasnt Has. unfold intersect.
  apply (@decs_has_concat_right l D (refine_decs Ds1 Ds2) Ds2).
  apply (@refine_decs_spec_unbound_preserved l Ds1 Ds2 Hasnt).
  assumption. 
Qed.

Lemma intersect_spec_12_typ: forall n S1 T1 S2 T2 Ds1 Ds2,
  decs_has Ds1                 (label_typ n) (dec_typ S1 T1) ->
  decs_has Ds2                 (label_typ n) (dec_typ S2 T2) ->
  decs_has (intersect Ds1 Ds2) (label_typ n) (dec_typ (t_or S1 S2) (t_and T1 T2)).
Proof.
  intros. unfold intersect. apply decs_has_concat_left.
  apply refine_decs_spec_typ; assumption.
Qed.

Lemma intersect_spec_12_fld: forall n T1 T2 Ds1 Ds2,
  decs_has Ds1                 (label_fld n) (dec_fld T1) ->
  decs_has Ds2                 (label_fld n) (dec_fld T2) ->
  decs_has (intersect Ds1 Ds2) (label_fld n) (dec_fld (t_and T1 T2)).
Proof.
  intros. unfold intersect. apply decs_has_concat_left.
  apply refine_decs_spec_fld; assumption.
Qed.

Lemma intersect_spec_12_mtd: forall n S1 T1 S2 T2 Ds1 Ds2,
  decs_has Ds1                 (label_mtd n) (dec_mtd S1 T1) ->
  decs_has Ds2                 (label_mtd n) (dec_mtd S2 T2) ->
  decs_has (intersect Ds1 Ds2) (label_mtd n) (dec_mtd (t_or S1 S2) (t_and T1 T2)).
Proof.
  intros. unfold intersect. apply decs_has_concat_left.
  apply refine_decs_spec_mtd; assumption.
Qed.

Lemma intersect_spec_hasnt: forall l Ds1 Ds2,
  decs_hasnt Ds1 l ->
  decs_hasnt Ds2 l ->
  decs_hasnt (intersect Ds1 Ds2) l.
Proof.
  introv Hasnt1 Hasnt2. unfold intersect. apply decs_hasnt_concat.
  + apply (refine_decs_spec_unbound_preserved _ Hasnt1).
  + apply Hasnt2.
Qed.

End DecsImpl.


(* ###################################################################### *)
(** ** Trivial inversion lemmas *)

Lemma invert_subdec_typ_sync_left_unused: forall m G D Lo2 Hi2,
   subdec m G           D       (dec_typ Lo2 Hi2) -> exists Lo1 Hi1,
   subdec m G (dec_typ Lo1 Hi1) (dec_typ Lo2 Hi2)
/\ D = (dec_typ Lo1 Hi1).
Proof.
  introv Sd. inversions Sd.
  + exists Lo2 Hi2. auto.
  + exists Lo1 Hi1. auto.
Qed.

Lemma invert_subdec_fld_sync_left_unused: forall m G D T2,
   subdec m G     D        (dec_fld T2) -> exists T1,
   subdec m G (dec_fld T1) (dec_fld T2)
/\ D = (dec_fld T1).
Proof.
  introv Sd. inversions Sd.
  + exists T2. auto.
  + exists T1. auto.
Qed.

Lemma invert_subdec_mtd_sync_left_unused: forall m G D T2 U2,
   subdec m G         D       (dec_mtd T2 U2) -> exists T1 U1,
   subdec m G (dec_mtd T1 U1) (dec_mtd T2 U2)
/\ D = (dec_mtd T1 U1).
Proof.
  introv Sd. inversions Sd.
  + exists T2 U2. auto.
  + exists S1 T1. auto.
Qed.

Lemma invert_subdec_typ_sync_left: forall m G D T2 U2,
   subdec m G D (dec_typ T2 U2) ->
   exists T1 U1, D = (dec_typ T1 U1) /\
                 subtyp m G T2 T1 /\
                 subtyp m G U1 U2.
Proof.
  introv Sd. inversions Sd.
  + exists T2 U2. apply (conj eq_refl).
    split; destruct m; try apply subtyp_mode; apply subtyp_refl.
  + exists Lo1 Hi1. apply (conj eq_refl). auto.
Qed.

Lemma invert_subdec_fld_sync_left: forall m G D T2,
   subdec m G D (dec_fld T2) ->
   exists T1, D = (dec_fld T1) /\
              subtyp m G T1 T2.
Proof.
  introv Sd. inversions Sd.
  + exists T2. apply (conj eq_refl).
    destruct m; try apply subtyp_mode; apply subtyp_refl.
  + exists T1. apply (conj eq_refl). assumption.
Qed.

Lemma invert_subdec_mtd_sync_left: forall m G D T2 U2,
   subdec m G D (dec_mtd T2 U2) ->
   exists T1 U1, D = (dec_mtd T1 U1) /\
                 subtyp m G T2 T1 /\
                 subtyp m G U1 U2.
Proof.
  introv Sd. inversions Sd.
  + exists T2 U2. apply (conj eq_refl).
    split; destruct m; try apply subtyp_mode; apply subtyp_refl.
  + exists S1 T1. apply (conj eq_refl). auto.
Qed.

(** *** Inversion lemmas for [wf_sto] *)

Lemma wf_sto_to_ok_s: forall s G,
  wf_sto s G -> ok s.
Proof. intros. induction H; jauto. Qed.

Lemma wf_sto_to_ok_G: forall s G,
  wf_sto s G -> ok G.
Proof. intros. induction H; jauto. Qed.

Hint Resolve wf_sto_to_ok_s wf_sto_to_ok_G.

Lemma ctx_binds_to_sto_binds: forall s G x T,
  wf_sto s G ->
  binds x T G ->
  exists o, binds x o s.
Proof.
  introv Wf Bi. gen x T Bi. induction Wf; intros.
  + false* binds_empty_inv.
  + unfolds binds. rewrite get_push in *. case_if.
    - eauto.
    - eauto.
Qed.

Lemma sto_binds_to_ctx_binds: forall s G x T ds,
  wf_sto s G ->
  binds x (object T ds) s ->
  binds x T G.
Proof.
  introv Wf Bi. gen x T Bi. induction Wf; intros.
  + false* binds_empty_inv.
  + unfolds binds. rewrite get_push in *. case_if.
    - inversions Bi. reflexivity.
    - auto.
Qed.

Lemma fresh_push_eq_inv: forall A x a (E: env A),
  x # (E & x ~ a) -> False.
Proof.
  intros. rewrite dom_push in H. false H. rewrite in_union.
  left. rewrite in_singleton. reflexivity.
Qed.

Lemma sto_unbound_to_ctx_unbound: forall s G x,
  wf_sto s G ->
  x # s ->
  x # G.
Proof.
  introv Wf Ub_s.
  induction Wf.
  + auto.
  + destruct (classicT (x0 = x)) as [Eq | Ne].
    - subst. false (fresh_push_eq_inv Ub_s). 
    - auto.
Qed.

Lemma ctx_unbound_to_sto_unbound: forall s G x,
  wf_sto s G ->
  x # G ->
  x # s.
Proof.
  introv Wf Ub.
  induction Wf.
  + auto.
  + destruct (classicT (x0 = x)) as [Eq | Ne].
    - subst. false (fresh_push_eq_inv Ub). 
    - auto.
Qed.

Lemma invert_wf_sto: forall s G,
  wf_sto s G ->
    forall x ds T T',
      binds x (object T ds) s -> 
      binds x T' G ->
      T' = T /\ exists G1 G2 Ds,
        G = G1 & x ~ T & G2 /\ 
        exp G1 T Ds /\
        ty_defs (G1 & x ~ T) (open_defs x ds) (open_decs x Ds) /\
        (forall L S U, decs_has (open_decs x Ds) L (dec_typ S U) -> 
                       subtyp notrans (G1 & x ~ T) S U).
(*
        (forall y, y \notin L ->
                   ty_defs (G1 & y ~ T) (open_defs y ds) (open_decs y Ds) /\
                   forall M S U, decs_has (open_decs y Ds) M (dec_typ S U) -> 
                                 subtyp notrans (G1 & y ~ T) S U).
*)
Proof.
  intros s G Wf. induction Wf; intros.
  + false* binds_empty_inv.
  + unfold binds in *. rewrite get_push in *.
    case_if.
    - inversions H4. inversions H5. split. reflexivity.
      exists G (@empty typ) Ds. rewrite concat_empty_r. auto.
    - specialize (IHWf x0 ds0 T0 T' H4 H5).
      destruct IHWf as [EqT [G1 [G2 [Ds0 [EqG [Exp [Ty F]]]]]]]. subst G T0.
      apply (conj eq_refl).
      exists G1 (G2 & x ~ T) Ds0.
      rewrite concat_assoc.
      apply (conj eq_refl). apply (conj Exp). auto.
Qed.


(** *** Inverting [phas] *)

(*
Lemma invert_phas: forall G x l D,
  phas G x l D ->
  exists T Ds D', binds x T G /\
                  exp G T Ds /\
                  decs_has Ds l (open_dec x D').
Proof.
  intros. inversion H. subst. exists T Ds D0. auto.
Qed.
*)

(*** Inverting [subdec] *)

Lemma subdec_to_label_for_eq: forall m G D1 D2 n,
  subdec m G D1 D2 ->
  (label_for_dec n D1) = (label_for_dec n D2).
Proof.
  introv Sd. inversions Sd; unfold label_for_dec; reflexivity.
Qed.

(** *** Inverting [subdecs] *)

Lemma invert_subdecs_push: forall m G Ds1 Ds2 n D2,
  subdecs m G Ds1 (decs_cons n D2 Ds2) -> 
    exists D1, decs_has Ds1 (label_for_dec n D2) D1
            /\ subdec m G D1 D2
            /\ subdecs m G Ds1 Ds2.
Proof.
  intros. inversions H. eauto.
Qed.

(** *** Inverting [has] *)

(*
Lemma invert_has: forall G t l D,
  has G t l D ->
  exists T Ds, ty_trm G t T /\ 
               exp G T Ds /\ 
               decs_has Ds l D /\
               (forall z : var, open_dec z D = D).
Proof.
  intros. inversions H. exists T Ds. auto.
Qed.
*)

(** *** Inverting [ty_def] *)

Lemma ty_def_to_label_for_eq: forall G d D n, 
  ty_def G d D ->
  label_for_def n d = label_for_dec n D.
Proof.
  intros. inversions H; reflexivity.
Qed.

(** *** Inverting [ty_defs] *)

Lemma extract_ty_def_from_ty_defs: forall G l d ds D Ds,
  ty_defs G ds Ds ->
  defs_has ds l d ->
  decs_has Ds l D ->
  ty_def G d D.
Proof.
  introv HdsDs. induction HdsDs.
  + intros. inversion H.
  + introv dsHas DsHas. unfolds defs_has, decs_has, get_def, get_dec. 
    rewrite (ty_def_to_label_for_eq n H) in dsHas. case_if.
    - inversions dsHas. inversions DsHas. assumption.
    - apply* IHHdsDs.
Qed.

Lemma invert_ty_mtd_inside_ty_defs: forall G ds Ds m S T body,
  ty_defs G ds Ds ->
  defs_has ds (label_mtd m) (def_mtd body) ->
  decs_has Ds (label_mtd m) (dec_mtd S T) ->
  (* conclusion is the premise needed to construct a ty_mtd: *)
  exists L, forall x, x \notin L -> ty_trm (G & x ~ S) (open_trm x body) T.
Proof.
  introv HdsDs dsHas DsHas.
  lets H: (extract_ty_def_from_ty_defs HdsDs dsHas DsHas).
  inversions* H. 
Qed.

Lemma invert_ty_fld_inside_ty_defs: forall G ds Ds l v T,
  ty_defs G ds Ds ->
  defs_has ds (label_fld l) (def_fld v) ->
  decs_has Ds (label_fld l) (dec_fld T) ->
  (* conclusion is the premise needed to construct a ty_fld: *)
  ty_trm G (trm_var v) T.
Proof.
  introv HdsDs dsHas DsHas.
  lets H: (extract_ty_def_from_ty_defs HdsDs dsHas DsHas).
  inversions* H. 
Qed.

Lemma get_def_cons : forall l n d ds,
  get_def l (defs_cons n d ds) = If l = (label_for_def n d) then Some d else get_def l ds.
Proof.
  intros. unfold get_def. case_if~.
Qed.

Lemma get_dec_cons : forall l n D Ds,
  get_dec l (decs_cons n D Ds) = If l = (label_for_dec n D) then Some D else get_dec l Ds.
Proof.
  intros. unfold get_dec. case_if~.
Qed.

Lemma decs_has_to_defs_has: forall G l ds Ds D,
  ty_defs G ds Ds ->
  decs_has Ds l D ->
  exists d, defs_has ds l d.
Proof.
  introv Ty Bi. induction Ty; unfolds decs_has, get_dec. 
  + discriminate.
  + unfold defs_has. folds get_dec. rewrite get_def_cons. case_if.
    - exists d. reflexivity.
    - rewrite <- (ty_def_to_label_for_eq n H) in Bi. case_if. apply (IHTy Bi).
Qed.


(* ###################################################################### *)
(** ** Uniqueness *)

Lemma exp_phas_unique:
  (forall G T Ds1 , exp G T Ds1   -> forall Ds2, exp G T Ds2   -> Ds1 = Ds2) /\ 
  (forall G v l D1, phas G v l D1 -> forall D2 , phas G v l D2 -> D1  = D2 ).
Proof.
  apply exp_phas_mutind; intros.
  + inversions H. reflexivity.
  + inversions H. reflexivity.
  + inversions H1. specialize (H _ H5). inversions H. apply* H0.
  + inversions H0. unfold decs_has in *.
    lets Eq: (binds_func b H1). subst.
    specialize (H _ H2). subst.
    rewrite d in H3. 
    inversion H3. reflexivity.
Qed.

Definition exp_unique  := (proj1 exp_phas_unique).
Definition phas_unique := (proj2 exp_phas_unique).

(* That would be so nice...
Lemma exp_unique: forall G T z Ds1 Ds2,
  exp G T z Ds1 -> exp G T z Ds2 -> Ds1 = Ds2
with phas_unique: forall G v X D1 D2, 
  phas G v X D1 -> phas G v X D2 -> D1 = D2.
Proof.
  + introv H1 H2.
    inversions H1; inversions H2.
    - reflexivity.
    - reflexivity.
    - lets Eq: (phas_unique _ _ _ _ _ H H5). inversions Eq.
      apply* exp_unique.
  + introv H1 H2.
    apply invert_phas in H1. destruct H1 as [T1 [Ds1 [Bi1 [Exp1 Has1]]]].
    apply invert_phas in H2. destruct H2 as [T2 [Ds2 [Bi2 [Exp2 Has2]]]].
    unfold decs_has in *.
    lets Eq: (binds_func Bi1 Bi2). subst.
    lets Eq: (exp_unique _ _ _ _ _ Exp1 Exp2). subst.
    rewrite Has2 in Has1. 
    inversion Has1. reflexivity.
Qed. (* Error: Cannot guess decreasing argument of fix. *)
*)

(* ###################################################################### *)

Lemma subdec_mode: forall G d1 d2,
  subdec notrans G d1 d2 -> subdec oktrans G d1 d2.
Proof.
  intros.
  inversion H; subst; auto.
Qed.

Lemma label_for_dec_open: forall z D n,
  label_for_dec n (open_dec z D) = label_for_dec n D.
Proof.
  intros. destruct D; reflexivity.
Qed.


(* The converse does not hold because
   [(open_dec z D1) = (open_dec z D2)] does not imply [D1 = D2]. *)
Lemma decs_has_open: forall Ds l D z,
  decs_has Ds l D -> decs_has (open_decs z Ds) l (open_dec z D).
Proof.
  introv Has. induction Ds.
  + inversion Has.
  + unfold open_decs, open_rec_decs. fold open_rec_decs. fold open_rec_dec.
    unfold decs_has, get_dec. case_if.
    - unfold decs_has, get_dec in Has. rewrite label_for_dec_open in Has. case_if.
      inversions Has. reflexivity.
    - fold get_dec. apply IHDs. unfold decs_has, get_dec in Has.
      rewrite label_for_dec_open in H. case_if. apply Has.
Qed.

Lemma decs_has_open_backwards: forall Ds l D z, z \notin fv_decs Ds ->
  decs_has (open_decs z Ds) l (open_dec z D) -> decs_has Ds l D.
Proof.
  introv Fr Has. induction Ds.
  + inversion Has.
  + unfold open_decs, open_rec_decs in Has.
    fold open_rec_decs in Has. fold open_rec_dec in Has.
    unfold decs_has, get_dec in Has. fold get_dec in Has. case_if.
    - unfold decs_has, get_dec. fold get_dec. rewrite label_for_dec_open. case_if.
      unfold open_dec in Has. inversions Has.
Admitted. (* reflexivity.
    - fold get_dec. apply IHDs. unfold decs_has, get_dec in Has.
      rewrite label_for_dec_open in H. case_if. apply Has.
Qed.*)


(* ###################################################################### *)
(** ** Weakening *)

Lemma weaken_exp_phas:
   (forall G T Ds, exp G T Ds -> 
      forall G1 G2 G3, G = G1 & G3 -> ok (G1 & G2 & G3) -> exp (G1 & G2 & G3) T Ds)
/\ (forall G x l D, phas G x l D ->
      forall G1 G2 G3, G = G1 & G3 -> ok (G1 & G2 & G3) -> phas (G1 & G2 & G3) x l D).
Proof.
  apply exp_phas_mutind; intros; subst.
  + apply exp_top.
  + apply exp_bind.
  + apply* exp_sel.
  + apply* phas_var. apply* binds_weaken.
Qed.

Lemma weaken_exp_middle: forall G1 G2 G3 T Ds,
  exp (G1 & G3) T Ds -> ok (G1 & G2 & G3) -> exp (G1 & G2 & G3) T Ds.
Proof.
  intros. apply* weaken_exp_phas.
Qed.

Lemma weaken_exp_end: forall G1 G2 T Ds,
  exp G1 T Ds -> ok (G1 & G2) -> exp (G1 & G2) T Ds.
Proof.
  introv Exp Ok.
  assert (Eq1: G1 = G1 & empty) by (rewrite concat_empty_r; reflexivity).
  assert (Eq2: G1 & G2 = G1 & G2 & empty) by (rewrite concat_empty_r; reflexivity).
  rewrite Eq1 in Exp. rewrite Eq2 in Ok. rewrite Eq2.
  apply (weaken_exp_middle Exp Ok).
Qed.

Lemma weaken_phas_middle: forall G1 G2 G3 v l D,
  phas (G1 & G3) v l D -> ok (G1 & G2 & G3) -> phas (G1 & G2 & G3) v l D.
Proof.
  intros. apply* weaken_exp_phas.
Qed.

Lemma weaken_phas_end: forall G1 G2 v l D,
  phas G1 v l D -> ok (G1 & G2) -> phas (G1 & G2) v l D.
Proof.
  introv Exp Ok.
  assert (Eq1: G1 = G1 & empty) by (rewrite concat_empty_r; reflexivity).
  assert (Eq2: G1 & G2 = G1 & G2 & empty) by (rewrite concat_empty_r; reflexivity).
  rewrite Eq1 in Exp. rewrite Eq2 in Ok. rewrite Eq2.
  apply (weaken_phas_middle Exp Ok).
Qed.

Lemma subtyp_and_subdec_and_subdecs_weaken:
   (forall m G T1 T2 (Hst : subtyp m G T1 T2),
      forall G1 G2 G3, ok (G1 & G2 & G3) ->
                       G1 & G3 = G ->
                       subtyp m (G1 & G2 & G3) T1 T2)
/\ (forall m G d1 d2 (Hsd : subdec m G d1 d2),
      forall G1 G2 G3, ok (G1 & G2 & G3) ->
                       G1 & G3 = G ->
                       subdec m (G1 & G2 & G3) d1 d2)
/\ (forall m G ds1 ds2 (Hsds : subdecs m G ds1 ds2),
      forall G1 G2 G3, ok (G1 & G2 & G3) ->
                       G1 & G3 = G ->
                       subdecs m (G1 & G2 & G3) ds1 ds2).
Proof.
  apply subtyp_mutind.

  (* subtyp *)
  + (* case refl *)
    introv Hok123 Heq; subst.
    apply (subtyp_refl _ _).
  + (* case top *)
    introv Hok123 Heq; subst.
    apply (subtyp_top _ _).
  + (* case bot *)
    introv Hok123 Heq; subst.
    apply (subtyp_bot _ _).
  + (* case bind *)
    introv Hc IH Hok123 Heq; subst.
    apply_fresh subtyp_bind as z.
    rewrite <- concat_assoc.
    refine (IH z _ G1 G2 (G3 & z ~ typ_bind Ds1) _ _).
    - auto.
    - rewrite concat_assoc. auto.
    - rewrite <- concat_assoc. reflexivity.
  + (* case asel_l *)
    introv Hhas Hst IH Hok123 Heq; subst.
    apply subtyp_sel_l with (S := S) (U := U).
    - apply weaken_phas_middle; assumption.
    - apply (IH G1 G2 G3 Hok123 eq_refl).
  + (* case asel_r *)
    introv Hhas Hst_SU IH_SU Hst_TS IH_TS Hok123 Heq; subst.
    apply subtyp_sel_r with (S := S) (U := U).
    - apply weaken_phas_middle; assumption.
    - apply IH_SU; auto.
    - apply IH_TS; auto.
  + (* case trans *)
    introv Hst IH Hok Heq. apply subtyp_mode. apply* IH.
  + (* case mode *)
    introv Hst12 IH12 Hst23 IH23 Hok123 Heq.
    specialize (IH12 G1 G2 G3 Hok123 Heq).
    specialize (IH23 G1 G2 G3 Hok123 Heq).
    apply (subtyp_trans IH12 IH23).

  (* subdec *)
  + (* case subdec_refl *)
    intros.
    apply subdec_refl.
  + (* case subdec_typ *)
    intros.
    apply subdec_typ; gen G1 G2 G3; assumption.
  + (* case subdec_fld *)
    intros.
    apply subdec_fld; gen G1 G2 G3; assumption.
  + (* case subdec_mtd *)
    intros.
    apply subdec_mtd; gen G1 G2 G3; assumption.

  (* subdecs *)
  + (* case subdecs_empty *)
    intros.
    apply subdecs_empty.
  + (* case subdecs_push *)
    introv Hb Hsd IHsd Hsds IHsds Hok123 Heq.
    apply (subdecs_push n Hb).
    apply (IHsd _ _ _ Hok123 Heq).
    apply (IHsds _ _ _ Hok123 Heq).
Qed.

Print Assumptions subtyp_and_subdec_and_subdecs_weaken.

Lemma subtyp_weaken_middle: forall m G1 G2 G3 S U,
  ok (G1 & G2 & G3) -> 
  subtyp m (G1      & G3) S U ->
  subtyp m (G1 & G2 & G3) S U.
Proof.
  destruct subtyp_and_subdec_and_subdecs_weaken as [W _].
  introv Hok123 Hst.
  specialize (W m (G1 & G3) S U Hst).
  specialize (W G1 G2 G3 Hok123).
  apply W.
  trivial.
Qed.

Lemma env_add_empty: forall (P: ctx -> Prop) (G: ctx), P G -> P (G & empty).
Proof.
  intros.
  assert ((G & empty) = G) by apply concat_empty_r.
  rewrite -> H0. assumption.
Qed.  

Lemma env_remove_empty: forall (P: ctx -> Prop) (G: ctx), P (G & empty) -> P G.
Proof.
  intros.
  assert ((G & empty) = G) by apply concat_empty_r.
  rewrite <- H0. assumption.
Qed.

Lemma subtyp_weaken_end: forall m G1 G2 S U,
  ok (G1 & G2) -> 
  subtyp m G1        S U ->
  subtyp m (G1 & G2) S U.
Proof.
  introv Hok Hst.
  apply (env_remove_empty (fun G0 => subtyp m G0 S U) (G1 & G2)).
  apply subtyp_weaken_middle.
  apply (env_add_empty (fun G0 => ok G0) (G1 & G2) Hok).
  apply (env_add_empty (fun G0 => subtyp m G0 S U) G1 Hst).
Qed.

(* If we only weaken at the end, i.e. from [G1] to [G1 & G2], the IH for the 
   [ty_new] case adds G2 to the end, so it takes us from [G1, x: Ds] 
   to [G1, x: Ds, G2], but we need [G1, G2, x: Ds].
   So we need to weaken in the middle, i.e. from [G1 & G3] to [G1 & G2 & G3].
   Then, the IH for the [ty_new] case inserts G2 in the middle, so it
   takes us from [G1 & G3, x: Ds] to [G1 & G2 & G3, x: Ds], which is what we
   need. *)

Lemma weakening:
   (forall G e l d (Hhas: has G e l d)
           G1 G2 G3 (Heq: G = G1 & G3) (Hok123: ok (G1 & G2 & G3)),
           has (G1 & G2 & G3) e l d ) 
/\ (forall G e T (Hty: ty_trm G e T)
           G1 G2 G3 (Heq: G = G1 & G3) (Hok123: ok (G1 & G2 & G3)),
           ty_trm (G1 & G2 & G3) e T) 
/\ (forall G i d (Hty: ty_def G i d)
           G1 G2 G3 (Heq: G = G1 & G3) (Hok123: ok (G1 & G2 & G3)), 
           ty_def (G1 & G2 & G3) i d)
/\ (forall G is Ds (Hisds: ty_defs G is Ds)
           G1 G2 G3 (Heq: G = G1 & G3) (Hok123: ok (G1 & G2 & G3)), 
           ty_defs (G1 & G2 & G3) is Ds).
Proof.
  apply ty_mutind; intros; subst.
  + assert (exp (G1 & G2 & G3) T Ds) by apply* weaken_exp_middle.
    apply* has_trm.
  + assert (exp (G1 & G2 & G3) T Ds) by apply* weaken_exp_middle.
    apply* has_var.
  + apply ty_var. apply* binds_weaken.
  + apply* ty_sel.
  + apply* ty_call.
  + apply_fresh ty_new as x.
    - apply* weaken_exp_phas.
    - rewrite <- concat_assoc. apply H.
      * auto.
      * rewrite concat_assoc. reflexivity.
      * rewrite concat_assoc. auto.
    - introv Has. rewrite <- concat_assoc. apply subtyp_weaken_middle.
      * rewrite concat_assoc. auto.
      * rewrite concat_assoc. apply* s.
  + apply ty_sbsm with T.
    - apply* H.
    - apply* subtyp_weaken_middle.
  + apply ty_typ. 
  + apply* ty_fld.
  + rename H into IH.
    apply_fresh ty_mtd as x.
    rewrite <- concat_assoc.
    refine (IH x _ G1 G2 (G3 & x ~ S) _ _).
    - auto.
    - symmetry. apply concat_assoc.
    - rewrite concat_assoc. auto.
  + apply ty_dsnil.
  + apply* ty_dscons.
Qed.

Print Assumptions weakening.

Lemma weaken_has: forall G1 G2 e l d,
  has G1 e l d -> ok (G1 & G2) -> has (G1 & G2) e l d.
Proof.
  intros.
  destruct weakening as [W _].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_trm: forall G1 G2 e T,
  ty_trm G1 e T -> ok (G1 & G2) -> ty_trm (G1 & G2) e T.
Proof.
  intros.
  destruct weakening as [_ [W _]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_def: forall G1 G2 i d,
  ty_def G1 i d -> ok (G1 & G2) -> ty_def (G1 & G2) i d.
Proof.
  intros.
  destruct weakening as [_ [_ [W _]]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_defs: forall G1 G2 is Ds,
  ty_defs G1 is Ds -> ok (G1 & G2) -> ty_defs (G1 & G2) is Ds.
Proof.
  intros.
  destruct weakening as [_ [_ [_ W]]].
  rewrite <- (concat_empty_r (G1 & G2)).
  apply (W (G1 & empty)); rewrite* concat_empty_r.
Qed.

Lemma weaken_ty_defs_middle: forall G1 G2 G3 ds Ds,
  ty_defs (G1 & G3) ds Ds -> ok (G1 & G2 & G3) -> ty_defs (G1 & G2 & G3) ds Ds.
Proof.
  intros. apply* weakening.
Qed.


(* ###################################################################### *)
(** ** The substitution principle *)


(*

without dependent types:

                  G, x: S |- e : T      G |- u : S
                 ----------------------------------
                            G |- [u/x]e : T

with dependent types:

                  G1, x: S, G2 |- t : T      G1 |- y : S
                 ---------------------------------------
                      G1, [y/x]G2 |- [y/x]t : [y/x]T


Note that in general, u is a term, but for our purposes, it suffices to consider
the special case where u is a variable.
*)

Lemma subst_label_for_dec: forall n x y D,
  label_for_dec n (subst_dec x y D) = label_for_dec n D.
Proof.
  intros. destruct D; reflexivity.
Qed.

Lemma subst_decs_has: forall x y Ds l D,
  decs_has Ds l D ->
  decs_has (subst_decs x y Ds) l (subst_dec x y D).
Proof.
  introv Has. induction Ds.
  + inversion Has.
  + unfold subst_decs, decs_has, get_dec. fold subst_decs subst_dec get_dec.
    rewrite subst_label_for_dec.
    unfold decs_has, get_dec in Has. fold get_dec in Has. case_if.
    - inversions Has. reflexivity.
    - apply* IHDs.
Qed.

Lemma subst_binds0: forall y S v T G1 G2 x,
    binds v T (G1 & x ~ S & G2) ->
    binds y S G1 ->
    ok (G1 & x ~ S & G2) ->
    binds (subst_fvar x y v) (subst_typ x y T) (G1 & (subst_ctx x y G2)).
Proof.
  intros y S v T G1. refine (env_ind _ _ _).
  + intros x Biv Biy Ok. unfold subst_ctx. rewrite map_empty.
    rewrite concat_empty_r in *. apply binds_push_inv in Biv.
    apply ok_push_inv in Ok. destruct Ok as [Ok xG1].
    destruct Biv as [[Eq1 Eq2] | [Ne Biv]].
    - subst. unfold subst_fvar. case_if.
      assert (subst_typ x y S = S) by admit. (* x # G1, so S cannot contain it *)
      rewrite H. apply Biy.
    - unfold subst_fvar. case_if. 
      assert (subst_typ x y T = T) by admit. (* x # G1, so T cannot contain it *)
      rewrite H0. apply Biv.
  + intros G2 x0 T0 IH x Biv Biy Ok. rewrite concat_assoc in *.
    apply ok_push_inv in Ok. destruct Ok as [Ok x0notin].
    assert (x0x: x0 <> x) by admit.
    apply binds_push_inv in Biv. destruct Biv as [[Eq1 Eq2] | [Ne Biv]].
    - subst x0 T0. unfold subst_ctx. rewrite map_push. rewrite concat_assoc.
      unfold subst_fvar. case_if. apply binds_push_eq.
    - unfold subst_fvar. case_if.
(* TODO...*)
Abort.

Lemma subst_binds1: forall v T G1 x y S G2,
  binds v T (G1 & x ~ S & G2) ->
  binds y S G1 ->
  x <> v ->
  binds v (subst_typ x y T) (G1 & subst_ctx x y G2).
Proof.
Abort.

Lemma subst_binds: forall x y v T G,
  binds v T G ->
  binds v (subst_typ x y T) (subst_ctx x y G).
Proof.
  introv Bi. unfold subst_ctx. apply binds_map. exact Bi.
Qed.

(** Note: We use [binds y S G1] instead of [ty_trm G1 (trm_var (avar_f y)) S]
    to exclude the subsumption case. *)
Lemma subst_exp_phas: forall y S,
   (forall G T Ds, exp G T Ds -> forall G1 G2 x, G = G1 & x ~ S & G2 ->
      binds y S G1 ->
      ok (G1 & x ~ S & G2) ->
      exp (G1 & (subst_ctx x y G2)) (subst_typ x y T) (subst_decs x y Ds))
/\ (forall G v l D, phas G v l D -> forall G1 G2 x, G = G1 & x ~ S & G2 ->
      binds y S G1 ->
      ok (G1 & x ~ S & G2) ->
      phas (G1 & (subst_ctx x y G2)) (subst_fvar x y v) l (subst_dec x y D)). 
Proof.
  intros y S. apply exp_phas_mutind.
  (* case exp_top *)
  + intros. simpl. apply exp_top.
  (* case exp_bind *)
  + intros. simpl. apply exp_bind.
  (* case exp_sel *)
  + intros G v L Lo Hi Ds Has IHHas Exp IHExp G1 G2 x EqG Tyy Ok. subst G.
    specialize (IHHas _ _ _ eq_refl Tyy Ok).
    specialize (IHExp _ _ _ eq_refl Tyy Ok).
    unfold subst_typ. unfold subst_pth. unfold subst_avar. case_if.
    - unfold subst_fvar in IHHas. case_if.
      apply (exp_sel IHHas IHExp).
    - unfold subst_fvar in IHHas. case_if.
      apply (exp_sel IHHas IHExp).
  (* case phas_var *)
  + intros G v T Ds l D Bi Exp IH Has G1 G2 x EqG Tyy Ok. subst G.
    specialize (IH _ _ _ eq_refl Tyy Ok).
    unfold subst_fvar. case_if.
    - (* case x = v *)
      apply (fun b => binds_middle_eq_inv b Ok) in Bi. subst.
      rewrite (subst_open_commute_dec v y v D). unfold subst_fvar. case_if.
      refine (phas_var _ IH _).
      * (* v is after G1, so it cannot occur in S *)
        assert (Eq: (subst_typ v y S) = S) by admit. rewrite Eq.
        apply (binds_concat_left Tyy).
        rewrite <- concat_assoc in Ok. assert (y # G2) by admit.
        admit.
      * apply (subst_decs_has _ _ Has).
    - (* case x <> v *)
      rewrite (subst_open_commute_dec x y v D). unfold subst_fvar. case_if.
      refine (phas_var _ IH _).
      * apply binds_concat_inv in Bi. destruct Bi as [Bi | [vG2 Bi]].
        { apply binds_concat_right. apply (subst_binds _ _ Bi). }
        { assert (Ne: v <> x) by auto. apply (fun b => binds_push_neq_inv b Ne) in Bi.
          assert (Eq: (subst_typ x y T) = T) by admit. rewrite Eq.
          apply (binds_concat_left Bi).
          admit. }
      * apply (subst_decs_has _ _ Has).
Qed.

Lemma subst_phas: forall G1 G2 x y S v l D,
  phas (G1 & x ~ S & G2) v l D ->
  binds y S G1 ->
  ok (G1 & x ~ S & G2) ->
  phas (G1 & (subst_ctx x y G2)) (subst_fvar x y v) l (subst_dec x y D).
Proof.
  intros. apply* subst_exp_phas.
Qed.

Lemma if_same: forall (T: Type) (P: Prop) (t: T), (If P then t else t) = t.
Proof.
  intros. case_if; reflexivity.
Qed.

Lemma subtyping_subst_principles: forall y S,
   (forall m G T U, subtyp m G T U -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     binds y S G1 ->
     ok (G1 & (x ~ S) & G2) ->
     subtyp m (G1 & (subst_ctx x y G2)) (subst_typ x y T) (subst_typ x y U))
/\ (forall m G D1 D2, subdec m G D1 D2 -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     binds y S G1 ->
     ok (G1 & (x ~ S) & G2) ->
     subdec m (G1 & (subst_ctx x y G2)) (subst_dec x y D1) (subst_dec x y D2))
/\ (forall m G Ds1 Ds2, subdecs m G Ds1 Ds2 -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     binds y S G1 ->
     ok (G1 & (x ~ S) & G2) ->
     subdecs m (G1 & (subst_ctx x y G2)) (subst_decs x y Ds1) (subst_decs x y Ds2)).
Proof.
  intros y S. apply subtyp_mutind.
  + (* case subtyp_refl *)
    intros. apply subtyp_refl.
  + (* case subtyp_top *)
    intros. simpl. apply subtyp_top.
  + (* case subtyp_bot *)
    intros. simpl. apply subtyp_bot.
  + (* case subtyp_bind *)
    intros L G Ds1 Ds2 Sds IH G1 G2 x Eq Bi Ok. subst.
    apply_fresh subtyp_bind as z. fold subst_decs.
    assert (zL: z \notin L) by auto.
    specialize (IH z zL G1 (G2 & z ~ typ_bind Ds1) x).
    rewrite concat_assoc in IH.
    specialize (IH eq_refl Bi).
    unfold subst_ctx in IH. rewrite map_push in IH. simpl in IH.
    rewrite concat_assoc in IH.
    rewrite (subst_open_commute_decs x y z Ds1) in IH.
    rewrite (subst_open_commute_decs x y z Ds2) in IH.
    unfold subst_fvar in IH.
    assert (x <> z) by auto. case_if.
    unfold subst_ctx. apply IH. admit.
  + (* case subtyp_sel_l *)
    intros G v L Lo Hi T Has St IH G1 G2 x Eq Bi Ok. subst.
    specialize (IH _ _ _ eq_refl Bi Ok).
    simpl.
    lets P: (subst_phas Has Bi Ok). simpl in P. unfold subst_fvar in P.
    case_if; case_if; apply (subtyp_sel_l P IH).
  + (* case subtyp_sel_r *)
    intros G v L Lo Hi T Has St1 IH1 St2 IH2 G1 G2 x Eq Bi Ok. subst.
    specialize (IH1 _ _ _ eq_refl Bi Ok).
    specialize (IH2 _ _ _ eq_refl Bi Ok).
    simpl.
    lets P: (subst_phas Has Bi Ok). simpl in P. unfold subst_fvar in P.
    case_if; case_if; apply (subtyp_sel_r P IH1 IH2).
  + (* case subtyp_mode *)
    intros G T1 T2 St IH G1 G2 x Eq Bi Ok. subst.
    specialize (IH _ _ _ eq_refl Bi Ok).
    apply (subtyp_mode IH).
  + (* case subtyp_trans *)
    intros G T1 T2 T3 St12 IH12 St23 IH23 G1 G2 x Eq Bi Ok. subst.
    apply* subtyp_trans.
  + (* case subdec_refl *)
    intros. destruct m. 
    - apply subdec_refl.
    - apply subdec_mode. apply subdec_refl.
  + (* case subdec_typ *)
    intros. apply* subdec_typ.
  + (* case subdec_fld *)
    intros. apply* subdec_fld.
  + (* case subdec_mtd *)
    intros. apply* subdec_mtd.
  + (* case subdecs_empty *)
    intros. apply subdecs_empty.
  + (* case subdecs_push *)
    intros m G n Ds1 Ds2 D1 D2 Has Sd IH1 Sds IH2 G1 G2 x Eq Bi Ok. subst.
    specialize (IH1 _ _ _ eq_refl Bi Ok).
    specialize (IH2 _ _ _ eq_refl Bi Ok).
    apply (subst_decs_has x y) in Has.
    rewrite <- (subst_label_for_dec n x y D2) in Has.
    apply subdecs_push with (subst_dec x y D1); 
      fold subst_dec; fold subst_decs; assumption.
Qed.

Print Assumptions subtyping_subst_principles.

Lemma subdecs_subst_principle: forall m G x y S Ds1 Ds2,
  ok (G & x ~ S) ->
  subdecs m (G & x ~ S) Ds1 Ds2 ->
  binds y S G ->
  subdecs m G (subst_decs x y Ds1) (subst_decs x y Ds2).
Proof.
  introv Hok Sds yTy. destruct (subtyping_subst_principles y S) as [_ [_ P]].
  specialize (P m _ Ds1 Ds2 Sds G empty x).
  unfold subst_ctx in P. rewrite map_empty in P.
  repeat (progress (rewrite concat_empty_r in P)).
  apply* P.
Qed.

Lemma trm_subst_principles: forall y S,
   (forall G t l D, has G t l D -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     binds y S G1 ->
     ok (G1 & (x ~ S) & G2) ->
     has (G1 & (subst_ctx x y G2)) (subst_trm x y t) l (subst_dec x y D))
/\ (forall G t T, ty_trm G t T -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     binds y S G1 ->
     ok (G1 & (x ~ S) & G2) ->
     ty_trm (G1 & (subst_ctx x y G2)) (subst_trm x y t) (subst_typ x y T))
/\ (forall G d D, ty_def G d D -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     binds y S G1 ->
     ok (G1 & (x ~ S) & G2) ->
     ty_def (G1 & (subst_ctx x y G2)) (subst_def x y d) (subst_dec x y D))
/\ (forall G ds Ds, ty_defs G ds Ds -> forall G1 G2 x,
     G = (G1 & (x ~ S) & G2) ->
     binds y S G1 ->
     ok (G1 & (x ~ S) & G2) ->
     ty_defs (G1 & (subst_ctx x y G2)) (subst_defs x y ds) (subst_decs x y Ds)).
Proof.
  intros y S.
  apply ty_mutind.
  + (* case has_trm *)
    intros G t T Ds l D Ty IH Exp Has Clo G1 G2 x EqG Bi Ok.
    subst G. specialize (IH _ _ _ eq_refl Bi Ok).
    apply has_trm with (subst_typ x y T) (subst_decs x y Ds).
    - exact IH.
    - apply* subst_exp_phas.
    - apply* subst_decs_has.
    - intro z. specialize (Clo z). admit.
  + (* case has_var *)
    intros G z T Ds l D Ty IH Exp Has G1 G2 x EqG Bi Ok.
    subst G. specialize (IH _ _ _ eq_refl Bi Ok). simpl in *. case_if.
    - (* case z = x *)
      rewrite (subst_open_commute_dec x y x D). unfold subst_fvar. case_if.
      apply has_var with (subst_typ x y T) (subst_decs x y Ds).
      * exact IH.
      * apply* subst_exp_phas.
      * apply (subst_decs_has x y Has).
    - (* case z <> x *)
      rewrite (subst_open_commute_dec x y z D). unfold subst_fvar. case_if.
      apply has_var with (subst_typ x y T) (subst_decs x y Ds).
      * exact IH.
      * apply* subst_exp_phas.
      * apply (subst_decs_has x y Has).
  + (* case ty_var *)
    intros G z T Biz G1 G2 x EqG Biy Ok.
    subst G. unfold subst_trm, subst_avar. case_var.
    - (* case z = x *)
      assert (EqST: T = S) by apply (binds_middle_eq_inv Biz Ok). subst. 
      apply ty_var.
      assert (yG2: y # (subst_ctx x y G2)) by admit.
      refine (binds_concat_left _ yG2).
      assert (xG1: x # G1) by admit.
      assert (Eq: (subst_typ x y S) = S) by admit.
      rewrite Eq. assumption.
    - (* case z <> x *)
      apply ty_var. admit.
  (* case ty_sel *)
  + intros G t l T Has IH G1 G2 x Eq Bi Ok. apply* ty_sel.
  (* case ty_call *)
  + intros G t m U V u Has IHt Tyu IHu G1 G2 x Eq Bi Ok. apply* ty_call.
  (* case ty_new *)
  + intros L G T ds Ds Exp Tyds IH F G1 G2 x Eq Bi Ok. subst G.
    apply_fresh ty_new as z.
    - apply* subst_exp_phas.
    - fold subst_defs.
      lets C: (@subst_open_commute_defs x y z ds).
      unfolds open_defs. unfold subst_fvar in C. case_var.
      rewrite <- C.
      lets D: (@subst_open_commute_decs x y z Ds).
      unfolds open_defs. unfold subst_fvar in D. case_var.
      rewrite <- D.
      rewrite <- concat_assoc.
      assert (zL: z \notin L) by auto.
      specialize (IH z zL G1 (G2 & z ~ T) x). rewrite concat_assoc in IH.
      specialize (IH eq_refl Bi).
      unfold subst_ctx in IH. rewrite map_push in IH. unfold subst_ctx.
      apply IH. auto.
    - intros M Lo Hi Has.
      assert (zL: z \notin L) by auto. specialize (F z zL M Lo Hi).
      admit.
  (* case ty_sbsm *)
  + intros G t T U Ty IH St G1 G2 x Eq Bi Ok. subst.
    apply ty_sbsm with (subst_typ x y T).
    - apply* IH.
    - apply* subtyping_subst_principles.
  (* case ty_typ *)
  + intros. simpl. apply ty_typ.
  (* case ty_fld *)
  + intros. apply* ty_fld.
  (* case ty_mtd *)
  + intros L G T U t Ty IH G1 G2 x Eq Bi Ok. subst.
    apply_fresh ty_mtd as z. fold subst_trm. fold subst_typ.
    lets C: (@subst_open_commute_trm x y z t).
    unfolds open_trm. unfold subst_fvar in C. case_var.
    rewrite <- C.
    rewrite <- concat_assoc.
    assert (zL: z \notin L) by auto.
    specialize (IH z zL G1 (G2 & z ~ T) x). rewrite concat_assoc in IH.
    specialize (IH eq_refl Bi).
    unfold subst_ctx in IH. rewrite map_push in IH. unfold subst_ctx.
    apply IH. auto.
  (* case ty_dsnil *)
  + intros. apply ty_dsnil.
  (* case ty_dscons *)
  + intros. apply* ty_dscons.
Qed.

Print Assumptions trm_subst_principles.

Lemma trm_subst_principle: forall G x y t S T,
  ok (G & x ~ S) ->
  ty_trm (G & x ~ S) t T ->
  binds y S G ->
  ty_trm G (subst_trm x y t) (subst_typ x y T).
Proof.
  introv Hok tTy yTy. destruct (trm_subst_principles y S) as [_ [P _]].
  specialize (P _ t T tTy G empty x).
  unfold subst_ctx in P. rewrite map_empty in P.
  repeat (progress (rewrite concat_empty_r in P)).
  apply* P.
Qed.


(* ###################################################################### *)
(** ** Transitivity *)

(*
(* "reflexive subdec", just subdec+reflexivity *)
Definition rsubdec(G: ctx)(D1 D2: dec): Prop :=
  D1 = D2 \/ subdec oktrans G D1 D2.
Definition rsubdecs(G: ctx)(Ds1 Ds2: decs): Prop :=
  Ds1 = Ds2 \/ subdecs oktrans G Ds1 Ds2.
*)

Hint Constructors exp phas.
Hint Constructors subtyp subdec subdecs.

Lemma subdecs_add_left_new: forall m n G Ds2 D1 Ds1,
  decs_hasnt Ds2 (label_for_dec n D1) ->
  subdecs m G Ds1 Ds2 ->
  subdecs m G (decs_cons n D1 Ds1) Ds2.
Proof.
  introv Hasnt. induction Ds2; intro Sds.
  + apply subdecs_empty.
  + rename d into D2. inversions Sds.
    unfold decs_hasnt, get_dec in Hasnt. case_if. fold get_dec in Hasnt.
    apply subdecs_push with D0.
    - unfold decs_has, get_dec. case_if. fold get_dec. apply H5.
    - assumption. 
    - apply IHDs2; assumption.
Qed.

Lemma subdecs_add_left_dupl: forall m n G Ds2 D1 Ds1,
  decs_has Ds1 (label_for_dec n D1) D1 ->
  subdecs m G Ds1 Ds2 ->
  subdecs m G (decs_cons n D1 Ds1) Ds2.
Proof.
Abort.

(* that's subdecs_push+subdec_refl:
Lemma subdecs_add_right_eq: forall m n G 
  decs_has Ds1 (label_for_dec n D) D ->
  subdecs m G Ds1 Ds2 ->
  subdecs m G Ds1 (decs_cons n D Ds2).
*)

Lemma subdecs_remove_left: forall m n G Ds2 D1 Ds1,
  decs_hasnt Ds2 (label_for_dec n D1) ->
  subdecs m G (decs_cons n D1 Ds1) Ds2 ->
  subdecs m G Ds1 Ds2.
Proof.
  introv Hasnt. induction Ds2; intro Sds.
  + apply subdecs_empty.
  + rename d into D2. inversions Sds.
    unfold decs_hasnt, get_dec in Hasnt. case_if. fold get_dec in Hasnt.
    apply subdecs_push with D0.
    - unfold decs_has, get_dec in H5. case_if. fold get_dec in H5. apply H5.
    - assumption.
    - apply IHDs2; assumption.
Qed.

Lemma subdecs_remove_right: forall m n G Ds2 D2 Ds1,
  (* need Ds2 hasn't n, because it might shadow something conflicting *)
  decs_hasnt Ds2 (label_for_dec n D2) ->
  subdecs m G Ds1 (decs_cons n D2 Ds2) ->
  subdecs m G Ds1 Ds2.
Proof.
  introv Hasnt. induction Ds2; intro Sds.
  + apply subdecs_empty.
  + rename d into D0. inversions Sds. assumption.
Qed.

(*
Lemma subdecs_skip: forall m G Ds n D,
  decs_hasnt Ds (label_for_dec n D) ->
  subdecs m G (decs_cons n D Ds) Ds.
Proof.
  intros m G Ds. induction Ds; intros.
  + apply subdecs_empty.
  + rename D into D0, d into D.
    unfold decs_hasnt, get_dec in H. case_if. fold get_dec in H.
    apply subdecs_push with D.
    - unfold decs_has, get_dec. case_if. case_if. reflexivity.
    - apply subdec_refl.
    - apply IHDs. 
*)

Lemma decide_decs_has: forall Ds l,
  decs_hasnt Ds l \/ exists D, decs_has Ds l D.
Admitted.

Lemma invert_subdecs: forall m G Ds1 Ds2,
  subdecs m G Ds1 Ds2 -> 
  forall l D2, decs_has Ds2 l D2 -> 
               (exists D1, decs_has Ds1 l D1 /\ subdec m G D1 D2).
Proof.
  introv Sds. induction Ds2; introv Has.
  + inversion Has.
  + inversions Sds.
    unfold decs_has, get_dec in Has. case_if.
    - inversions Has.
      exists D1. split; assumption.
    - fold get_dec in Has. apply IHDs2; assumption.
Qed.

(* subdecs_refl does not hold, because subdecs requires that for each dec in rhs
   (including hidden ones), there is an unhidden one in lhs *)
(* or that there are no hidden decs in rhs *)
Lemma subdecs_refl: forall m G Ds,
  subdecs m G Ds Ds.
Proof.
Admitted. (* TODO does not hold!! *)

Lemma narrow_binds: forall x T G1 y (S1 S2: typ) G2,
  x <> y ->
  binds x T (G1 & y ~ S1 & G2) ->
  binds x T (G1 & y ~ S2 & G2).
Proof.
  introv Ne Bi. apply binds_middle_inv in Bi.
  destruct Bi as [Bi | [[Fr [Eq1 Eq2]] | [Fr [Neq Bi]]]]; subst; auto. false* Ne.
Qed.

Definition vars_empty: vars := \{}.

Lemma decs_has_preserves_sub: forall G Ds1 Ds2 l D2,
  decs_has Ds2 l D2 ->
  subdecs oktrans G Ds1 Ds2 ->
  exists D1, decs_has Ds1 l D1 /\ subdec oktrans G D1 D2.
Proof.
  introv Has Sds. induction Ds2.
  + inversion Has.
  + unfold decs_has, get_dec in Has. inversions Sds. case_if.
    - inversions Has. exists D1. auto.
    - fold get_dec in Has. apply* IHDs2.
Qed.

Print Assumptions decs_has_preserves_sub.

Lemma decs_has_preserves_sub_with_open_decs: forall G Ds1 Ds2 l D2 x,
  decs_has (open_decs x Ds2) l (open_dec x D2) ->
  subdecs oktrans G (open_decs x Ds1) (open_decs x Ds2) ->
  exists D1, decs_has (open_decs x Ds1) l (open_dec x D1) /\ 
             subdec oktrans G (open_dec x D1) (open_dec x D2).
Proof. Admitted. (*
  introv Has Sds. induction Ds2.
  + inversion Has.
  + unfold decs_has, get_dec in Has. inversions Sds. case_if.
    - inversions Has. exists D1. auto.
    - fold get_dec in Has. apply* IHDs2.
Qed.*)

(** transitivity in oktrans mode (trivial) *)
Lemma subtyp_trans_oktrans: forall G T1 T2 T3,
  subtyp oktrans G T1 T2 -> subtyp oktrans G T2 T3 -> subtyp oktrans G T1 T3.
Proof.
  introv H12 H23.
  apply (subtyp_trans H12 H23).
Qed.

Lemma subdec_trans_oktrans: forall G d1 d2 d3,
  subdec oktrans G d1 d2 -> subdec oktrans G d2 d3 -> subdec oktrans G d1 d3.
Proof.
  introv H12 H23. inversions H12; inversions H23; constructor;
  solve [ assumption | (eapply subtyp_trans_oktrans; eassumption)].
Qed.

Lemma subdecs_trans_oktrans: forall G Ds1 Ds2 Ds3,
  subdecs oktrans G Ds1 Ds2 ->
  subdecs oktrans G Ds2 Ds3 ->
  subdecs oktrans G Ds1 Ds3.
Proof.
  introv H12 H23.
  induction Ds3.
  + apply subdecs_empty.
  + rename d into D3.
    apply invert_subdecs_push in H23.
    destruct H23 as [D2 [H23a [H23b H23c]]].
    lets H12': (invert_subdecs H12).
    specialize (H12' _ _ H23a).
    destruct H12' as [D1 [Has Sd]].
    apply subdecs_push with D1.
    - assumption.
    - apply subdec_trans_oktrans with D2; assumption.
    - apply (IHDs3 H23c).
Qed.

Lemma subtyp_trans_oktrans_n: forall G x T1 T2 T3 Ds1 Ds2,
  subdecs oktrans (G & x ~ typ_bind Ds1) Ds1 Ds2 ->
  subtyp oktrans (G & x ~ typ_bind Ds1) T1 T2 -> 
  subtyp oktrans (G & x ~ typ_bind Ds2) T2 T3 -> 
  subtyp oktrans (G & x ~ typ_bind Ds1) T1 T3.
Proof.
  introv Sds H12 H23.
  (* for T1=T2, this is narrowing *)
Abort.

Lemma subdec_trans_oktrans_n: forall G x D1 D2 D3 Ds1 Ds2,
  subdecs oktrans (G & x ~ typ_bind Ds1) Ds1 Ds2 ->
  subdec oktrans (G & x ~ typ_bind Ds1) D1 D2 ->
  subdec oktrans (G & x ~ typ_bind Ds2) D2 D3 ->
  subdec oktrans (G & x ~ typ_bind Ds1) D1 D3.
Proof.
Admitted.

Lemma subdecs_trans_oktrans_n: forall G x Ds1 Ds2 Ds3,
  subdecs oktrans (G & x ~ typ_bind Ds1) Ds1 Ds2 ->
  subdecs oktrans (G & x ~ typ_bind Ds2) Ds2 Ds3 ->
  subdecs oktrans (G & x ~ typ_bind Ds1) Ds1 Ds3.
Proof.
  introv H12 H23.
  induction Ds3.
  + apply subdecs_empty.
  + rename d into D3.
    apply invert_subdecs_push in H23.
    destruct H23 as [D2 [H23a [H23b H23c]]].
    lets H12': (invert_subdecs H12).
    specialize (H12' _ _ H23a).
    destruct H12' as [D1 [Has Sd]].
    apply subdecs_push with D1.
    - assumption.
    - apply subdec_trans_oktrans_n with D2 Ds2; assumption.
    - apply (IHDs3 H23c).
Abort. (* does not work because it doesn't work for types *)

(* 
narrowing expansion does not work if we have precise phas, Bot in upper bounds 
and no expansion for Bot

   If  [G2 |- p has L:Bot..U]
   and [G1 |- p has L:Bot..Bot]
   then to narrow 
   [exp G2 p.L Ds2] into 
   [exp G1 p.L Ds1]
   we need either need imprecise [has] to say [G1 |- p.L has L:Bot..U]
   or we need an expansion for Bot.

But why does narrow-lk in oopsla/dot.elf work? Because
* narrow-lk is only proved for the case where all types of the
  environment which are narrowed are typ_bind (judgment "sev").
* there is no Bot, but lower bounds have a topt

Note: narrow-lk depends on extend-wf-mem and extend-wf-xp (= weakening for phas/exp)

xp and has-mem are unique

And why does narrowing has work in DotTransitivity?
* Because has only defined for variables of type typ_bind => no expansion needed.

Note that imprecise has means non-unique has => problems in transitivity pushing proof.
So we need an expansion for Bot.
*)

(* We only prove a limited form of narrowing, where we're narrowing from an [S2] to an
   [S1] and both of them are typ_bind. This allows us to exclude some sel cases,
   and we don't even need mutual induction with expansion. *)

(*
check narrow_phas statement at the end of these!

Lemma narrow_phas: forall v L G DB z Ds1 Ds2,
  subdecs oktrans   (G & z ~ typ_bind Ds1) Ds1 Ds2 ->
  ok                (G & z ~ typ_bind Ds2) ->
  phas              (G & z ~ typ_bind Ds2) v L DB ->
  exists DA, 
     subdec oktrans (G & z ~ typ_bind Ds1) DA DB
            /\ phas (G & z ~ typ_bind Ds1) v L DA.
Proof.
  intros v L. refine (env_ind _ _ _).
  + intros DB z Ds1 Ds2 Sds Ok Has. rewrite concat_empty_l in *.
    (* since typing only holds for locally closed expressions: *)
    assert (CloDs2: forall z, open_decs z Ds2 = Ds2) by admit.
    inversions Has.
    rename H into Bi, H0 into Exp, H1 into Has.
    apply binds_single_inv in Bi. destruct Bi as [Eq1 Eq2]. subst.
    inversions Exp.
    assert (CloD: forall z, open_dec z D = D) by admit.
    destruct (decs_has_preserves_sub Has Sds) as [DA [Has' Sd]].
    assert (CloDs1: forall z, open_decs z Ds1 = Ds1) by admit.
    assert (CloDA: forall z, open_dec z DA = DA) by admit.
    exists DA.
    rewrite CloD. apply (conj Sd). rewrite <- (CloDA z).
    apply phas_var with (typ_bind Ds1) Ds1.
    - apply binds_single_eq.
    - apply exp_bind.
    - apply Has'.
  + intros G z0 T0 IH DB z Ds1 Ds2 Sds Ok Has.
    inversions Has. rename H into Bi, H0 into Exp, H1 into Has.
    apply binds_push_inv in Bi. destruct Bi as [[Eq1 Eq2] | [Ne Bi]].
    - subst. inversions Exp.
      specialize (IH (open_dec z D) z Ds1 Ds).
      admit.
    - specialize (IH (open_dec z D) z Ds1 Ds).

Admitted.

Lemma narrow_phas: forall v L G0 G DB z Ds1 Ds2,
  G0 =              (G & z ~ typ_bind Ds2) ->
  subdecs oktrans   (G & z ~ typ_bind Ds1) Ds1 Ds2 ->
  ok                (G & z ~ typ_bind Ds2) ->
  phas              (G & z ~ typ_bind Ds2) v L DB ->
  exists DA, 
     subdec oktrans (G & z ~ typ_bind Ds1) DA DB
            /\ phas (G & z ~ typ_bind Ds1) v L DA.
Proof.
  intros v L. refine (env_ind _ _ _).
  + introv Eq Sds Ok Has. false (empty_push_inv Eq).
  + intros G0 z0 T0 IH G DB z Ds1 Ds2 Eq Sds Ok Has.
    apply eq_push_inv in Eq. destruct Eq as [Eq1 [Eq2 Eq3]]. subst.
    (* can use IH only if G non-empty --> no point in using G0 and equalitiy *)
    specialize (IH G DB z Ds1 Ds2). eq_refl).
    subst G x l. clear Has.
    rename H into Bi, H0 into Exp, H1 into Has, H5 into Eq.
    apply binds_single_inv in Bi. destruct Bi as [Eq1 Eq2]. subst v T.
    inversion Exp. subst G Ds0 Ds.
    destruct (decs_has_preserves_sub Has Sds) as [DA [Has' Sd]].

    apply (decs_has_open z) in Has.
    destruct (decs_has_preserves_sub Has Sds) as [DA [Has' Sd]].

Lemma narrow_exp_phas:
   (forall G0 T DsB, exp G0 T DsB -> forall G z Ds1 Ds2, 
      G0    =         (G & z ~ typ_bind Ds2) -> 
      ok              (G & z ~ typ_bind Ds2) ->
      subdecs oktrans (G & z ~ typ_bind Ds1) Ds1 Ds2 -> exists DsA, 
      subdecs oktrans (G & z ~ typ_bind Ds1) DsA DsB
               /\ exp (G & z ~ typ_bind Ds1) T DsA)
/\ (forall G0 v l DB, phas G0 v l DB -> forall G z Ds1 Ds2,
      G0    =         (G & z ~ typ_bind Ds2) -> 
      ok              (G & z ~ typ_bind Ds2) ->
      subdecs oktrans (G & z ~ typ_bind Ds1) Ds1 Ds2 -> exists DA,
      subdec  oktrans (G & z ~ typ_bind Ds1) DA DB
              /\ phas (G & z ~ typ_bind Ds1) v l DA).
Proof.
  apply exp_phas_mutind.
  + (* case exp_top *)
    intros. exists decs_nil. auto.
  + (* case exp_bind *)
    intros. exists Ds. split.
    - apply subdecs_refl.
    - apply exp_bind.
  + (* case exp_sel *)
    intros G0 x L Lo Hi DsB Has IH1 Exp IH2 G z Ds1 Ds2 Eq Ok Sds. subst G0.
    specialize (IH1 G z Ds1 Ds2 eq_refl Ok Sds).
    specialize (IH2 G z Ds1 Ds2 eq_refl Ok Sds).
    destruct IH1 as [DA [Sd' Has']].
    destruct IH2 as [DsA [Sds' Exp']]. exists DsA. apply (conj Sds').
    apply invert_subdec_sync_left in Sd'.
    destruct Sd' as [Lo' [Hi' [Sd' Eq]]]. subst DA.
    apply (exp_sel Has').
    admit. (* ??? *)
  + (* case phas_var *)
    intros G0 v T DsB l DB Bi Exp IH Has G z Ds1 Ds2 Eq Ok Sds. subst G0.
    specialize (IH G z Ds1 Ds2 eq_refl Ok Sds).
    destruct IH as [DsA [Sds' Exp']].
    destruct (decs_has_preserves_sub Has Sds') as [DA [Has' Sd]].
    exists (open_dec v DA).

   apply (decs_has_open x) in Has.
    destruct (decs_has_preserves_sub Has Sds) as [DA [Has' Sd]].
    assert (E: exists DA', open_dec x DA' = DA). admit. destruct E as [DA' Eq]. subst.
    exists (open_dec x DA'). split. assumption.
    assert (Ne: x <> y) by admit. (* contradicts Ok *)
    lets Bi': (narrow_binds S1 Ne Bi).
    apply (phas_var Bi' Exp').



Qed.


Lemma narrow_exp:
  forall G0 T DsB, exp G0 T DsB -> forall G z Ds1 Ds2, 
    G0    =         (G & z ~ typ_bind Ds2) -> 
    ok              (G & z ~ typ_bind Ds2) ->
    subdecs oktrans (G & z ~ typ_bind Ds1) Ds1 Ds2 -> exists DsA, 
    subdecs oktrans (G & z ~ typ_bind Ds1) DsA DsB
             /\ exp (G & z ~ typ_bind Ds1) T DsA.
Proof.
  refine (exp_ind _ _ _ _).
  + (* case exp_top *)
    intros. exists decs_nil. auto.
  + (* case exp_bind *)
    intros. exists Ds. split.
    - apply subdecs_refl.
    - apply exp_bind.
  + (* case exp_sel *)
    intros G0 x L Lo Hi DsB Has Exp IH G z Ds1 Ds2 Eq Ok Sds. subst G0.
    specialize (IH G z Ds1 Ds2 eq_refl Ok Sds).
    destruct IH as [DsA [Sds' Exp']]. exists DsA. apply (conj Sds').
    apply exp_sel with Lo Hi.

Qed.



    exp             (G & z ~ typ_bind Ds1) T

Lemma narrow_exp: forall G z Ds1 Ds2 T DsB,
  subdecs oktrans   (G & z ~ typ_bind Ds1) Ds1 Ds2 ->
  ok                (G & z ~ typ_bind Ds2) ->
  exp               (G & z ~ typ_bind Ds2) T DsB ->
  exists DsA, 
    subdecs oktrans (G & z ~ typ_bind Ds1) DsA DsB
             /\ exp (G & z ~ typ_bind Ds1) T DsA.
Proof.
  introv Sds Ok Exp. induction Exp.
  + (* case exp_top *)
    exists decs_nil. auto.
  + (* case exp_bind *)
    exists Ds. split.
    - apply subdecs_refl.
    - apply exp_bind.
  + (* case exp_sel *)
    rename H into Has.

Qed.


Lemma narrow_phas: forall G z Ds1 Ds2 p L DB,
  subdecs oktrans   (G & z ~ typ_bind Ds1) Ds1 Ds2 ->
  ok                (G & z ~ typ_bind Ds2) ->
  phas              (G & z ~ typ_bind Ds2) p L DB ->
  exists DA, 
     subdec oktrans (G & z ~ typ_bind Ds1) DA DB
            /\ phas (G & z ~ typ_bind Ds1) p L DA.
Proof.
  introv Sds Ok Has. inversions Has. rename H into Bi, H0 into Exp, H1 into Has.
  
Qed.

Lemma narrow_has: forall G x S1 S2 v l D2,
  phas (G1 & x ~ S2 & G2) v l D2 ->
  ok (G1 & x ~ S2 & G2) ->
  subtyp oktrans (G1 & x ~ S1) S1 S2 -> 
  exists D1, subdec oktrans (G1 & x ~ S1) D1 D2 /\
             phas (G1 & x ~ S1 & G2) v l D1.
Proof.
  introv Has Ok St. 
Qed.

Lemma narrow_exp_phas:
   (forall G T DsB, exp G T DsB -> 
     forall G1 G2 x S1 S2, 
       G = (G1 & x ~ S2 & G2) -> 
       ok G ->
       subtyp oktrans (G1 & x ~ S1) S1 S2 -> 
       exists   DsA, (forall z, 
                      subdecs oktrans (G1 & x ~ S1) (open_decs z DsA) (open_decs z DsB)) /\
                     exp (G1 & x ~ S1 & G2) T DsA)
/\ (forall G v l DB, phas G v l DB -> 
     forall G1 G2 x S1 S2, 
       G = (G1 & x ~ S2 & G2) ->
       ok G ->
       subtyp oktrans (G1 & x ~ S1) S1 S2 -> 
       exists DA, subdec oktrans (G1 & x ~ S1) DA DB /\
                  phas (G1 & x ~ S1 & G2) v l DA).
Proof.
  apply exp_phas_mutind.
  (* case exp_top *)
  + intros. exists decs_nil. auto.
  (* case exp_bind *)
  + intros. exists Ds. split. 
    - intro. apply subdecs_refl. (* does not hold! *)
    - apply exp_bind.
  (* case exp_sel *)
  + intros G x L Lo Hi Ds Has IH1 Exp IH2 G1 G2 y S1 S2 Eq OkG SubS1S2. subst G.
    specialize (IH1 G1 G2 y S1 S2 eq_refl OkG SubS1S2).
    destruct IH1 as [DA [Sd Has']].
    lets IH2': (IH2 G1 G2 y S1 S2 eq_refl OkG SubS1S2).
    destruct IH2' as [DsA [Sds Exp']].
    inversions Sd. 
    (* case subdec_refl *)
    - exists DsA. split. apply Sds. apply (exp_sel Has' Exp').
    (* case subdec_typ *)
    - exists DsA. split. assumption.
      apply (exp_sel Has'). (* apply Exp'.*) admit.

  (* case phas_var *)
  + intros G x T Ds l D Bi Exp IH Has G1 G2 y S1 S2 Eq OkG SubS1S2. subst G.
    specialize (IH G1 G2 y S1 S2 eq_refl OkG SubS1S2).
    destruct IH as [DsA [Sds Exp']].
    specialize (Sds x).
    apply (decs_has_open x) in Has.
    destruct (decs_has_preserves_sub Has Sds) as [DA [Has' Sd]].
    assert (E: exists DA', open_dec x DA' = DA). admit. destruct E as [DA' Eq]. subst.
    exists (open_dec x DA'). split. assumption.
    assert (Ne: x <> y) by admit. (* contradicts Ok *)
    lets Bi': (narrow_binds S1 Ne Bi).
    apply (phas_var Bi' Exp').


  (* case phas_var *)
  + intros G x T Ds l D Bi Exp IH Has G1 G2 y S1 S2 Eq OkG SubS1S2. subst G.
    specialize (IH G1 G2 y S1 S2 eq_refl OkG SubS1S2).
    destruct IH as [DsA [Sds Exp']].
    specialize (Sds x).
    apply (decs_has_open x) in Has.
    destruct (decs_has_preserves_sub_with_open_decs _ _ _ x Has Sds) as [DA [Has' Sd]].
    exists (open_dec x DA). split. assumption.
    assert (Ne: x <> y) by admit.
    lets Bi': (narrow_binds S1 Ne Bi).
    apply (phas_var Bi' Exp').


    destruct (decs_has_preserves_sub Has Sds) as [DA0 [Has0 Sd0]].
 Has').
Qed.
*)

(*
subdecs with only one specific z does not work
Lemma narrow_has: forall G1 G2 z Ds1 Ds2 x L DB,
  ok              (G1 & z ~ typ_bind Ds2 & G2) ->
  phas         (G1 & z ~ typ_bind Ds2 & G2) x L DB ->
  subdecs oktrans (G1 & z ~ typ_bind Ds1     ) (open_decs z Ds1) (open_decs z Ds2) ->
  exists DA,
    subdec oktrans (G1 & z ~ typ_bind Ds1     ) DA DB /\
    phas        (G1 & z ~ typ_bind Ds1 & G2) x L DA.
Proof.
  introv Ok Has Sd. destruct narrow_exp_phas as [_ P].
  refine (P (G1 & z ~ (typ_bind Ds2) & G2) _ _ _ Has _ _ _ 
            (typ_bind Ds1) (typ_bind Ds2) eq_refl Ok _).
  apply subtyp_mode. apply subtyp_bind.

Lemma narrow_has: forall G1 G2 z S1 S2 x L DB,
  ok             (G1 & z ~ S2 & G2) ->
  phas        (G1 & z ~ S2 & G2) x L DB ->
  subtyp oktrans (G1 & z ~ S1     ) S1 S2 ->
  exists DA,
    subdec oktrans (G1 & z ~ S1     ) DA DB /\
    phas        (G1 & z ~ S1 & G2) x L DA.
Proof.
  introv Ok Has Sd. destruct narrow_exp_phas as [_ P].
  apply (P (G1 & z ~ S2 & G2) _ _ _ Has _ _ _ S1 S2 eq_refl Ok Sd).
Qed.
*)


(* ###################################################################### *)
(** ** Narrowing *)

Definition only_typ_bind(G: ctx): Prop :=
  forall x T, binds x T G -> exists Ds, T = typ_bind Ds.

Definition only_exp_types(G1: ctx)(z: var)(U: typ)(G2: ctx): Prop :=
  forall G2a G2b x T, G2 = G2a & x ~ T & G2b -> exists Ds, exp (G1 & z ~ U & G2a) T Ds.

(*
Definition only_exp_types(G1: ctx)(z: var)(U: typ)(G2: ctx): Prop :=
   (exists Ds, exp G1 U Ds)
/\ (forall G2a G2b x T, G2 = G2a & x ~ T & G2b -> exists Ds, exp (G1 & z ~ U & G2a) T Ds).
*)

(*
Lemma narrow_phas: forall v L G1 G2 DB z Ds1 Ds2 S1,
  subdecs oktrans   (G1 & z ~ (typ_bind Ds1)) (open_decs z Ds1) (open_decs z Ds2) ->
  ok                (G1 & z ~ (typ_bind Ds2) & G2) ->
  only_exp_types     G1   z   S1               G2  ->
  phas              (G1 & z ~ (typ_bind Ds2) & G2) v L DB ->
  exp G1 S1 Ds1 ->
  exists DA, 
     subdec oktrans (G1 & z ~ S1     ) DA DB
            /\ phas (G1 & z ~ S1 & G2) v L DA.
Proof.
  introv Sds Ok Only Has Exp1. inversions Has. rename H into Bi, H0 into Exp, H1 into Has.
  unfold only_exp_types in Only.
  apply binds_middle_inv in Bi. destruct Bi as [Bi | [[vG2 [Eq1 Eq2]] | [vG2 [Ne Bi]]]].
  + (* v in G2 *)
    assert (Bi': exists G2a G2b, G2 = G2a & v ~ T & G2b) by admit.
    destruct Bi' as [G2a [G2b Eq]]. subst.
    specialize (Only G2a G2b v T eq_refl). destruct Only as [Ds' Exp']. subst.
    repeat progress (rewrite concat_assoc in * ).
    assert (Ok': ok (G1 & z ~ S1 & G2a & (v ~ T & G2b))) by admit.
    lets Exp'': (weaken_exp_end Exp' Ok').
    repeat progress (rewrite concat_assoc in * ).
    assert (Ds' = Ds) by admit. (* uniqueness of exp *) subst.
    exists (open_dec v D). apply (conj (subdec_refl _ _ _)).
    apply phas_var with T Ds; auto. apply binds_middle_eq. admit.

  + (* v in G2 *)
    assert (Bi': exists G2a G2b, G2 = G2a & v ~ T & G2b) by admit.
    destruct Bi' as [G2a [G2b Eq]]. subst.
    destruct Only as [Only1 Only2].
    specialize (Only2 G2a G2b v T eq_refl). destruct Only2 as [Ds' Exp']. subst.
    repeat progress (rewrite concat_assoc in * ).
    assert (Ok': ok (G1 & z ~ S1 & G2a & (v ~ T & G2b))) by admit.
    lets Exp'': (weaken_exp_end Exp' Ok').
    repeat progress (rewrite concat_assoc in * ).
    assert (Ds' = Ds) by admit. (* uniqueness of exp *) subst.
    exists (open_dec v D). apply (conj (subdec_refl _ _ _)).
    apply phas_var with T Ds; auto. apply binds_middle_eq. admit.
  + (* v = z *)
    subst. destruct Only as [[Ds' Exp'] Only].
    apply (decs_has_open z) in Has. inversions Exp. rename Ds into Ds2.
    destruct (decs_has_preserves_sub_with_open_decs _ _ _ _ Has Sds) as [DA [Has' Sd]].
    exists (open_dec z DA). apply (conj Sd). apply phas_var with S1 Ds'.
    - auto.
    - rewrite <- concat_assoc. apply (weaken_exp_end Exp'). admit.
    - assert (z \notin fv_decs Ds'). admit.
      apply (decs_has_open_backwards _ _ H Has'). 
  + (* v in G1 *)
    exists (open_dec v D). apply (conj (subdec_refl _ _ _)).
    assert (Exp': exp G1 T Ds) by admit. (* because T is wf in G1 *)
    rewrite <- concat_assoc.
    apply weaken_phas_end.
    - apply phas_var with T Ds; assumption.
    - rewrite concat_assoc. admit.
Qed.
*)

Lemma narrow_phas: forall v L G1 G2 DB z Ds1 Ds2,
  subdecs oktrans   (G1 & z ~ (typ_bind Ds1)     ) (open_decs z Ds1) (open_decs z Ds2) ->
  ok                (G1 & z ~ (typ_bind Ds2) & G2) ->
  only_exp_types     G1   z   (typ_bind Ds1)   G2  ->
  phas              (G1 & z ~ (typ_bind Ds2) & G2) v L DB ->
  exists DA, 
     subdec oktrans (G1 & z ~ (typ_bind Ds1)     ) DA DB
            /\ phas (G1 & z ~ (typ_bind Ds1) & G2) v L DA.
Proof.
  introv Sds Ok Only Has. inversions Has. rename H into Bi, H0 into Exp, H1 into Has.
  unfold only_exp_types in Only.
  apply binds_middle_inv in Bi. destruct Bi as [Bi | [[vG2 [Eq1 Eq2]] | [vG2 [Ne Bi]]]].
  + (* v in G2 *)
    assert (Bi': exists G2a G2b, G2 = G2a & v ~ T & G2b) by admit.
    destruct Bi' as [G2a [G2b Eq]]. subst.
    specialize (Only G2a G2b v T eq_refl). destruct Only as [Ds' Exp']. subst.
    repeat progress (rewrite concat_assoc in *).
    assert (Ok': ok (G1 & z ~ typ_bind Ds1 & G2a & (v ~ T & G2b))) by admit.
    lets Exp'': (weaken_exp_end Exp' Ok').
    repeat progress (rewrite concat_assoc in *).
    assert (Ds' = Ds) by admit. (* uniqueness of exp *) subst.
    exists (open_dec v D). apply (conj (subdec_refl _ _ _)).
    apply phas_var with T Ds; auto. apply binds_middle_eq. admit.
  + (* v = z *)
    subst. inversions Exp.
    apply (decs_has_open z) in Has.
    destruct (decs_has_preserves_sub_with_open_decs _ _ _ _ Has Sds) as [DA [Has' Sd]].
    exists (open_dec z DA). apply (conj Sd). apply phas_var with (typ_bind Ds1) Ds1.
    - auto.
    - apply exp_bind.
    - assert (z \notin fv_decs Ds1). admit.
      apply (decs_has_open_backwards _ _ H Has'). 
  + (* v in G1 *)
    exists (open_dec v D). apply (conj (subdec_refl _ _ _)).
    assert (Exp': exp G1 T Ds) by admit. (* because T is wf in G1 *)
    rewrite <- concat_assoc.
    apply weaken_phas_end.
    - apply phas_var with T Ds; assumption.
    - rewrite concat_assoc. admit.
Qed.

Lemma narrow_phas_0: forall v L G1 G2 DB z Ds1 Ds2,
  subdecs oktrans   (G1 & z ~ typ_bind Ds1     ) (open_decs z Ds1) (open_decs z Ds2) ->
  ok                (G1 & z ~ typ_bind Ds2 & G2) ->
  only_typ_bind                              G2  ->
  phas              (G1 & z ~ typ_bind Ds2 & G2) v L DB ->
  exists DA, 
     subdec oktrans (G1 & z ~ typ_bind Ds1     ) DA DB
            /\ phas (G1 & z ~ typ_bind Ds1 & G2) v L DA.
Proof.
  introv Sds Ok Only Has. inversions Has. rename H into Bi, H0 into Exp, H1 into Has.
  unfold only_typ_bind in Only.
  apply binds_middle_inv in Bi. destruct Bi as [Bi | [[vG2 [Eq1 Eq2]] | [vG2 [Ne Bi]]]].
  + (* v in G2 *)
    specialize (Only v T Bi). destruct Only as [Ds' Eq]. subst.
    inversions Exp.
    exists (open_dec v D). apply (conj (subdec_refl _ _ _)).
    apply phas_var with (typ_bind Ds) Ds; auto.
  + (* v = z *)
    subst. inversions Exp.
    apply (decs_has_open z) in Has.
    destruct (decs_has_preserves_sub_with_open_decs _ _ _ _ Has Sds) as [DA [Has' Sd]].
    exists (open_dec z DA). apply (conj Sd). apply phas_var with (typ_bind Ds1) Ds1.
    - auto.
    - apply exp_bind.
    - assert (z \notin fv_decs Ds1). admit.
      apply (decs_has_open_backwards _ _ H Has'). 
  + (* v in G1 *)
    exists (open_dec v D). apply (conj (subdec_refl _ _ _)).
    assert (Exp': exp G1 T Ds) by admit. (* because T is wf in G1 *)
    rewrite <- concat_assoc.
    assert (weaken_phas:
      phas (G1                          ) v L (open_dec v D) ->
      phas (G1 & (z ~ typ_bind Ds1 & G2)) v L (open_dec v D)) by admit.
    apply weaken_phas.
    apply phas_var with T Ds; assumption.
Qed.

Lemma narrow_phas_old: forall v L G1 G2 DB z Ds1 Ds2,
  subdecs oktrans   (G1 & z ~ typ_bind Ds1     ) (open_decs z Ds1) (open_decs z Ds2) ->
  ok                (G1 & z ~ typ_bind Ds2 & G2) ->
  phas              (G1 & z ~ typ_bind Ds2 & G2) v L DB ->
  exists DA, 
     subdec oktrans (G1 & z ~ typ_bind Ds1     ) DA DB
            /\ phas (G1 & z ~ typ_bind Ds1 & G2) v L DA.
Abort.

Lemma subtyp_and_subdec_and_subdecs_narrow:
   (forall m G T1 T2 (Hst : subtyp m G T1 T2), forall G1 G2 z DsA DsB, 
     ok              (G1 & z ~ typ_bind DsB & G2) ->
     G       =       (G1 & z ~ typ_bind DsB & G2) ->
     only_exp_types   G1   z  (typ_bind DsA)  G2  ->
     subdecs oktrans (G1 & z ~ typ_bind DsA     ) (open_decs z DsA) (open_decs z DsB) ->
     subtyp  oktrans (G1 & z ~ typ_bind DsA & G2) T1 T2)
/\ (forall m G D1 D2 (Hsd : subdec m G D1 D2), forall G1 G2 z DsA DsB, 
     ok              (G1 & z ~ typ_bind DsB & G2) ->
     G       =       (G1 & z ~ typ_bind DsB & G2) ->
     only_exp_types   G1   z  (typ_bind DsA)  G2  ->
     subdecs oktrans (G1 & z ~ typ_bind DsA     ) (open_decs z DsA) (open_decs z  DsB) ->
     subdec  oktrans (G1 & z ~ typ_bind DsA & G2) D1 D2)
/\ (forall m G Ds1 Ds2 (Hsds : subdecs m G Ds1 Ds2), forall G1 G2 z DsA DsB, 
     ok              (G1 & z ~ typ_bind DsB & G2) ->
     G       =       (G1 & z ~ typ_bind DsB & G2) ->
     only_exp_types   G1   z  (typ_bind DsA)  G2  ->
     subdecs oktrans (G1 & z ~ typ_bind DsA     ) (open_decs z DsA) (open_decs z DsB) ->
     subdecs oktrans (G1 & z ~ typ_bind DsA & G2) Ds1 Ds2).
Proof.
  apply subtyp_mutind; try (intros; solve [auto]).

  (* subtyp *)
  (* cases refl, top, bot: auto *)
  + (* case bind *)
    introv Hc IH Hok123 Heq Only HAB; subst. apply subtyp_mode.
    apply_fresh subtyp_bind as z0.
    rewrite <- concat_assoc.
    refine (IH z0 _ G1 (G2 & z0 ~ typ_bind Ds1) _ DsA DsB _ _ _ _); clear IH.
    - auto. 
    - rewrite concat_assoc. auto.
    - rewrite <- concat_assoc. reflexivity. 
    - unfold only_exp_types in *.
      intros G2a G2b x T Eq. destruct (env_case G2b) as [Eq'|[z0' [Z0' [G2c Eq']]]]; subst.
      * rewrite concat_empty_r in Eq. 
        (*assert (G2a = G2) by admit.
        assert (x = z0) by admit.*)
        assert (T = typ_bind Ds1) by admit. subst.
        exists Ds1. apply exp_bind.
      * rewrite concat_assoc in Eq.
        assert (Eq': G2 = G2a & x ~ T & G2c) by admit.
        apply (Only _ _ _ _ Eq').
    - assumption.
  + (* case sel_l *)
    introv Hhas Hst IH Hok Heq Only HAB; subst.
    apply subtyp_mode.
    lets Hn: (@narrow_phas _ _ _ _ _ _ DsA DsB HAB Hok Only Hhas).
    destruct Hn as [dA [Hrsd Hh]].
    inversions Hrsd.
    - (* case refl *)
      apply subtyp_sel_l with (S := S) (U := U).
      * assumption.
      * apply IH with (DsB0 := DsB); auto.
    - (* case not-refl *)
      apply subtyp_sel_l with (S := Lo1) (U := Hi1).
      assumption.
      assert (Hok': ok (G1 & z ~ (typ_bind DsA) & G2)).
      apply (ok_middle_change _ Hok).
      refine (subtyp_trans (subtyp_weaken_end Hok' H7) _).
      apply IH with (DsB0 := DsB); auto.
  + (* case asel_r *)
    introv Hhas Hst_SU IH_SU Hst_TS IH_TS Hok Heq Only HAB; subst.
    apply subtyp_mode.
    assert (Hok': ok (G1 & z ~ (typ_bind DsA) & G2)).
    apply (ok_middle_change _ Hok).
    lets Hn: (@narrow_phas _ _ _ _ _ _ DsA DsB HAB Hok Only Hhas).
    destruct Hn as [dA [Hrsd Hh]].
    inversions Hrsd.
    (* case refl *)
    - apply subtyp_sel_r with (S := S) (U := U).
      * assumption.
      * apply IH_SU with (DsB0 := DsB); auto.
      * apply IH_TS with (DsB0 := DsB); auto.
    (* case not-refl *)
    - apply subtyp_sel_r with (S := Lo1) (U := Hi1).
      assumption.
      apply (subtyp_weaken_end Hok' H1).
      refine (subtyp_trans _ (subtyp_weaken_end Hok' H6)).
      apply IH_TS with (DsB0 := DsB); auto.
  (* case trans *)
  + introv Hst IH Hok Heq Only HAB.
    apply subtyp_trans with (T2 := T2).
    - apply IH with (DsB := DsB); auto.
    - apply (subtyp_mode (subtyp_refl _ T2)).
  (* case mode *)
  + introv Hst12 IH12 Hst23 IH23 Hok123 Heq Only HAB.
    specialize (IH12 G1 G2 z DsA DsB Hok123 Heq Only HAB).
    specialize (IH23 G1 G2 z DsA DsB Hok123 Heq Only HAB).
    apply (subtyp_trans IH12 IH23).

  (* subdec *)
  (* case subdec_typ *)
  + intros. apply* subdec_typ.
  (* case subdec_fld *)
  + intros. apply* subdec_fld.
  (* case subdec_mtd *)
  + intros. apply* subdec_mtd.

  (* subdecs *)
  (* case subdecs_empty: auto *)
  (* case subdecs_push *)
  + introv Hb Hsd IHsd Hsds IHsds Hok123 Heq Only HAB.
    apply (subdecs_push n Hb).
    apply (IHsd  _ _ _ _ _ Hok123 Heq Only HAB).
    apply (IHsds _ _ _ _ _ Hok123 Heq Only HAB).
Qed.


Lemma subdec_narrow: forall G1 G2 z Ds1 Ds2 DA DB,
  ok              (G1 & z ~ typ_bind Ds2 & G2) ->
  only_exp_types   G1   z  (typ_bind Ds1)  G2  ->
  subdec  oktrans (G1 & z ~ typ_bind Ds2 & G2) DA DB ->
  subdecs oktrans (G1 & z ~ typ_bind Ds1     ) (open_decs z Ds1) (open_decs z Ds2) ->
  subdec  oktrans (G1 & z ~ typ_bind Ds1 & G2) DA DB.
Proof.
  introv Hok Only HAB Hsds.
  destruct subtyp_and_subdec_and_subdecs_narrow as [_ [N _]].
  specialize (N oktrans (G1 & z ~ typ_bind Ds2 & G2) DA DB).
  apply (N HAB G1 G2 z Ds1 Ds2 Hok eq_refl Only Hsds).
Qed.

Lemma subdecs_narrow: forall G1 G2 z Ds1 Ds2 DsA DsB,
  ok              (G1 & z ~ typ_bind Ds2 & G2) ->
  only_exp_types   G1   z  (typ_bind Ds1)  G2  ->
  subdecs oktrans (G1 & z ~ typ_bind Ds2 & G2) DsA DsB ->
  subdecs oktrans (G1 & z ~ typ_bind Ds1     ) (open_decs z Ds1) (open_decs z Ds2) ->
  subdecs oktrans (G1 & z ~ typ_bind Ds1 & G2) DsA DsB.
Proof.
  introv Hok HAB Hsds.
  destruct subtyp_and_subdec_and_subdecs_narrow as [_ [_ N]].
  specialize (N oktrans (G1 & z ~ typ_bind Ds2 & G2) DsA DsB).
  apply* N.
Qed.

Lemma subdec_narrow_last: forall G z Ds1 Ds2 DA DB,
  ok              (G & z ~ typ_bind Ds2) ->
  subdec  oktrans (G & z ~ typ_bind Ds2) DA DB ->
  subdecs oktrans (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds2) ->
  subdec  oktrans (G & z ~ typ_bind Ds1) DA DB.
Proof.
  introv Hok HAB H12.
  apply (env_remove_empty (fun G0 => subdec oktrans G0 DA DB) (G & z ~ typ_bind Ds1)).
  apply subdec_narrow with (Ds2 := Ds2).
  + apply (env_add_empty (fun G0 => ok G0) (G & z ~ typ_bind Ds2) Hok).
  + unfold only_exp_types. introv Eq. false (empty_middle_inv Eq).
  + apply (env_add_empty (fun G0 => subdec oktrans G0 DA DB)
                             (G & z ~ typ_bind Ds2) HAB).
  + assumption.
Qed.

Print Assumptions subdec_narrow_last.

Lemma subdecs_narrow_last: forall G z Ds1 Ds2 DsA DsB,
  ok              (G & z ~ typ_bind Ds2) ->
  subdecs oktrans (G & z ~ typ_bind Ds2) DsA DsB ->
  subdecs oktrans (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds2) ->
  subdecs oktrans (G & z ~ typ_bind Ds1) DsA DsB.
Proof.
  introv Hok H2AB H112.
  apply (env_remove_empty (fun G0 => subdecs oktrans G0 DsA DsB) (G & z ~ typ_bind Ds1)).
  apply subdecs_narrow with (Ds2 := Ds2).
  + apply (env_add_empty (fun G0 => ok G0) (G & z ~ typ_bind Ds2) Hok).
  + unfold only_exp_types. introv Eq. false (empty_middle_inv Eq).
  + apply (env_add_empty (fun G0 => subdecs oktrans G0 DsA DsB)
                             (G & z ~ typ_bind Ds2) H2AB).
  + assumption.
Qed.

Print Assumptions subdecs_narrow_last.


(* ... transitivity in notrans mode, but no p.L in middle ... *)

Lemma subtyp_trans_notrans: forall G T1 T2 T3,
  ok G -> notsel T2 -> subtyp notrans G T1 T2 -> subtyp notrans G T2 T3 -> 
  subtyp notrans G T1 T3.
Proof.
  introv Hok Hnotsel H12 H23.

  inversion Hnotsel; subst.
  (* case top *)
  + inversion H23; subst.
    apply (subtyp_top G T1).
    apply (subtyp_top G T1).
    apply (subtyp_sel_r H H0 (subtyp_trans (subtyp_mode H12) H1)).
  (* case bot *)
  + inversion H12; subst.
    apply (subtyp_bot G T3).
    apply (subtyp_bot G T3).
    apply (subtyp_sel_l H (subtyp_trans H0 (subtyp_mode H23))).
  (* case bind *)
  + inversion H12; inversion H23; subst; (
      assumption ||
      apply subtyp_refl ||
      apply subtyp_top ||
      apply subtyp_bot ||
      idtac
    ).
    (* bind <: bind <: bind *)
    - rename Ds into Ds2.
      apply_fresh subtyp_bind as z.
      assert (zL: z \notin L) by auto.
      assert (zL0: z \notin L0) by auto.
      specialize (H0 z zL).
      specialize (H4 z zL0).
      assert (Hok' : ok (G & z ~ typ_bind Ds1)) by auto.
      assert (Hok'': ok (G & z ~ typ_bind Ds2)) by auto.
      lets H4' : (subdecs_narrow_last Hok'' H4 H0). 
      apply (subdecs_trans_oktrans H0 H4').
    - (* bind <: bind <: sel  *)
      assert (H1S: subtyp oktrans G (typ_bind Ds1) S).
      apply (subtyp_trans_oktrans (subtyp_mode H12) H5).
      apply (subtyp_sel_r H3 H4 H1S).
    - (* sel  <: bind <: bind *)
      assert (HU2: subtyp oktrans G U (typ_bind Ds2)).
      apply (subtyp_trans_oktrans H0 (subtyp_mode H23)).
      apply (subtyp_sel_l H HU2). 
    - (* sel  <: bind <: sel  *)
      apply (subtyp_sel_r H1 H5).
      apply (subtyp_trans_oktrans (subtyp_mode H12) H6).
Qed.

Print Assumptions subtyp_trans_notrans.

(**
(follow_ub G p1.X1 T) means that there exists a chain

    (p1.X1: _ .. p2.X2), (p2.X2: _ .. p3.X3), ... (pN.XN: _ .. T)

which takes us from p1.X1 to T
*)
Inductive follow_ub : ctx -> typ -> typ -> Prop :=
  | follow_ub_nil : forall G T,
      follow_ub G T T
  | follow_ub_cons : forall G v X Lo Hi T,
      phas G v X (dec_typ Lo Hi) ->
      follow_ub G Hi T ->
      follow_ub G (typ_sel (pth_var (avar_f v)) X) T.

(**
(follow_lb G T pN.XN) means that there exists a chain

    (p1.X1: T .. _), (p2.X2: p1.X1 .. _), (p3.X3: p2.X2 .. _),  (pN.XN: pN-1.XN-1 .. _)

which takes us from T to pN.XN
*)
Inductive follow_lb: ctx -> typ -> typ -> Prop :=
  | follow_lb_nil : forall G T,
      follow_lb G T T
  | follow_lb_cons : forall G v X Lo Hi U,
      phas G v X (dec_typ Lo Hi) ->
      subtyp oktrans G Lo Hi -> (* <-- realizable bounds *)
      follow_lb G (typ_sel (pth_var (avar_f v)) X) U ->
      follow_lb G Lo U.

Hint Constructors follow_ub.
Hint Constructors follow_lb.

Lemma invert_follow_lb: forall G T1 T2,
  follow_lb G T1 T2 -> 
  T1 = T2 \/ 
    exists v1 X1 v2 X2 Hi, (typ_sel (pth_var (avar_f v2)) X2) = T2 /\
      phas G v1 X1 (dec_typ T1 Hi) /\
      subtyp oktrans G T1 Hi /\
      follow_lb G (typ_sel (pth_var (avar_f v1)) X1) (typ_sel (pth_var (avar_f v2)) X2).
Proof.
  intros.
  induction H.
  auto.
  destruct IHfollow_lb as [IH | IH].
  subst.
  right. exists v X v X Hi. auto.
  right.
  destruct IH as [p1 [X1 [p2 [X2 [Hi' [Heq [IH1 [IH2 IH3]]]]]]]].
  subst.  
  exists v X p2 X2 Hi.
  auto.
Qed.

(* Note: No need for a invert_follow_ub lemma because inversion is smart enough. *)

Definition st_middle (G: ctx) (B C: typ): Prop :=
  B = C \/
  subtyp notrans G typ_top C \/
  (notsel B /\ subtyp notrans G B C).

(* linearize a derivation that uses transitivity *)

Definition chain (G: ctx) (A D: typ): Prop :=
   (exists B C, follow_ub G A B /\ st_middle G B C /\ follow_lb G C D).

Lemma empty_chain: forall G T, chain G T T.
Proof.
  intros.
  unfold chain. unfold st_middle.
  exists T T.
  auto.
Qed.

Lemma chain3subtyp: forall G C1 C2 D, 
  subtyp notrans G C1 C2 ->
  follow_lb G C2 D -> 
  subtyp notrans G C1 D.
Proof.
  introv Hst Hflb.
  induction Hflb.
  assumption.
  apply IHHflb.
  apply (subtyp_sel_r H H0 (subtyp_mode Hst)).
Qed.

Lemma chain2subtyp: forall G B1 B2 C D,
  ok G ->
  subtyp notrans G B1 B2 ->
  st_middle G B2 C ->
  follow_lb G C D ->
  subtyp notrans G B1 D.
Proof.
  introv Hok Hst Hm Hflb.
  unfold st_middle in Hm.
  destruct Hm as [Hm | [Hm | [Hm1 Hm2]]]; subst.
  apply (chain3subtyp Hst Hflb).
  apply (chain3subtyp (subtyp_trans_notrans Hok notsel_top (subtyp_top G B1) Hm) Hflb).
  apply (chain3subtyp (subtyp_trans_notrans Hok Hm1 Hst Hm2) Hflb).
Qed.

Lemma chain1subtyp: forall G A B C D,
  ok G ->
  follow_ub G A B ->
  st_middle G B C ->
  follow_lb G C D ->
  subtyp notrans G A D.
Proof.
  introv Hok Hfub Hm Hflb.
  induction Hfub.
  apply (chain2subtyp Hok (subtyp_refl G T) Hm Hflb).
  apply (subtyp_sel_l H).
  apply subtyp_mode.
  apply (IHHfub Hok Hm Hflb).
Qed.


(* prepend an oktrans to chain ("utrans0*") *)
Lemma prepend_chain: forall G A1 A2 D,
  ok G ->
  subtyp oktrans G A1 A2 ->
  chain G A2 D ->
  chain G A1 D.
Proof.
  introv Hok St. unfold chain in *. unfold st_middle in *.
  induction St; intro Hch.
  + (* case refl *)
    assumption.
  + (* case top *)
    destruct Hch as [B [C [Hch1 [Hch2 Hch3]]]].
    inversion Hch1; subst.
    destruct Hch2 as [Hch2 | [Hch2 | [Hch2a Hch2b]]]; subst.
    exists T typ_top.
    auto 10.
    exists T C.
    auto 10.
    exists T C.
    auto 10.
  + (* case bot *)
    destruct Hch as [B [C [Hch1 [Hch2 Hch3]]]].
    exists typ_bot C.
    auto 10.
  + (* case bind *)
    destruct Hch as [B [C [Hch1 [Hch2 Hch3]]]].
    inversion Hch1; subst.
    exists (typ_bind Ds1) C.
    assert (subtyp notrans G (typ_bind Ds1) (typ_bind Ds2))
      by (apply subtyp_bind with L; assumption).
    destruct Hch2 as [Hch2 | [Hch2 | [Hch2a Hch2b]]].
    - subst. auto 10.
    - auto 10.
    - set (Hst := (subtyp_trans_notrans Hok (notsel_bind _) H0 Hch2b)). auto 10.
  + (* case asel_l *)
    specialize (IHSt Hok Hch).
    destruct IHSt as [B [C [IH1 [IH2 IH3]]]].
    exists B C.
    split.
    apply (follow_ub_cons H IH1).
    split; assumption.
  (*
  + (* case asel_r *) 
    apply (IHSt2 Hok). apply (IHSt1 Hok).
    destruct Hch as [B [C [Hch1 [Hch2 Hch3]]]].
    exists B C.
    inversions Hch1. (* oops, cannot prove follow_ub G U (typ_sel (pth_var (avar_f x)) L)*)
  *)
  + (* case asel_r *) 
    set (Hch' := Hch).
    destruct Hch' as [B [C [Hch1 [Hch2 Hch3]]]].
    inversion Hch1; subst.
    - (* case follow_ub_nil *)
      destruct Hch2 as [Hch2 | [Hch2 | [Hch2a Hch2b]]].
      * subst.
        apply (IHSt2 Hok).
        exists S S. 
        set (Hflb := (follow_lb_cons H St1 Hch3)).
        auto.
      * exists T C.
        auto.
      * inversion Hch2a. (* contradiction *)
    - (* case follow_ub_cons *)
      apply (IHSt2 Hok). apply (IHSt1 Hok).
      assert (HdecEq: dec_typ Lo Hi = dec_typ S U) by admit (* has_var_unique *).
      injection HdecEq; intros; subst.
      exists B C. auto.
  + (* case mode *)
    apply (IHSt Hok Hch).
  + (* case trans *)
    apply (IHSt1 Hok). apply (IHSt2 Hok Hch).
Qed.

Lemma oktrans_to_notrans: forall G T1 T3,
  ok G -> subtyp oktrans G T1 T3 -> subtyp notrans G T1 T3.
Proof.
  introv Hok Hst.
  assert (Hch: chain G T1 T3).
  apply (prepend_chain Hok Hst (empty_chain _ _)).
  unfold chain in Hch.
  destruct Hch as [B [C [Hch1 [Hch2 Hch3]]]].
  apply (chain1subtyp Hok Hch1 Hch2 Hch3).
Qed.

Print Assumptions oktrans_to_notrans.


(* ###################################################################### *)
(** ** More inversion lemmas *)

Lemma invert_var_has_dec: forall G x l D,
  has G (trm_var (avar_f x)) l D ->
  exists T Ds D', ty_trm G (trm_var (avar_f x)) T /\
                  exp G T Ds /\
                  decs_has Ds l D' /\
                  open_dec x D' = D.
Proof.
  introv Has. inversions Has.
  (* case has_trm *)
  + subst. exists T Ds D. auto.
  (* case has_var *)
  + exists T Ds D0. auto.
Qed.

Lemma invert_has: forall G t l D,
   has G t l D ->
   (exists T Ds,      ty_trm G t T /\
                      exp G T Ds /\
                      decs_has Ds l D /\
                      (forall z : var, open_dec z D = D))
\/ (exists x T Ds D', t = (trm_var (avar_f x)) /\
                      ty_trm G (trm_var (avar_f x)) T /\
                      exp G T Ds /\
                      decs_has Ds l D' /\
                      open_dec x D' = D).
Proof.
  introv Has. inversions Has.
  (* case has_trm *)
  + subst. left. exists T Ds. auto.
  (* case has_var *)
  + right. exists v T Ds D0. auto.
Qed.

Lemma invert_var_has_fld: forall G x l T,
  has G (trm_var (avar_f x)) l (dec_fld T) ->
  exists X Ds T', ty_trm G (trm_var (avar_f x)) X /\
                  exp G X Ds /\
                  decs_has Ds l (dec_fld T') /\
                  open_typ x T' = T.
Proof.
  introv Has. apply invert_var_has_dec in Has.
  destruct Has as [X [Ds [D [Tyx [Exp [Has Eq]]]]]].
  destruct D as [ Lo Hi | T' | T1 T2 ]; try solve [ inversion Eq ].
  unfold open_dec, open_rec_dec in Eq. fold open_rec_typ in Eq.
  inversion Eq as [Eq'].
  exists X Ds T'. auto.
Qed.

Lemma invert_var_has_mtd: forall G x l S U,
  has G (trm_var (avar_f x)) l (dec_mtd S U) ->
  exists X Ds S' U', ty_trm G (trm_var (avar_f x)) X /\
                     exp G X Ds /\
                     decs_has Ds l (dec_mtd S' U') /\
                     open_typ x S' = S /\
                     open_typ x U' = U.
Proof.
  introv Has. apply invert_var_has_dec in Has.
  destruct Has as [X [Ds [D [Tyx [Exp [Has Eq]]]]]].
  destruct D as [ Lo Hi | T' | S' U' ]; try solve [ inversion Eq ].
  unfold open_dec, open_rec_dec in Eq. fold open_rec_typ in Eq.
  inversion Eq as [Eq'].
  exists X Ds S' U'. auto.
Qed.

(** *** Inverting [ty_trm] *)

Lemma invert_ty_var: forall G x T,
  ty_trm G (trm_var (avar_f x)) T ->
  exists T', subtyp oktrans G T' T /\ binds x T' G.
Proof.
  introv Ty. gen_eq t: (trm_var (avar_f x)). gen x.
  induction Ty; intros x' Eq; try (solve [ discriminate ]).
  + inversions Eq. exists T. auto.
  + subst. specialize (IHTy _ eq_refl). destruct IHTy as [T' [St Bi]].
    exists T'. split.
    - apply subtyp_trans with T; assumption.
    - exact Bi.
Qed.

Lemma invert_ty_sel_var: forall G x l T,
  ty_trm G (trm_sel (trm_var (avar_f x)) l) T ->
  has G (trm_var (avar_f x)) (label_fld l) (dec_fld T).
Proof.
  introv Ty. gen_eq t0: (trm_sel (trm_var (avar_f x)) l). gen x l.
  induction Ty; try (solve [ intros; discriminate ]).
  (* base case: no subsumption *)
  + intros x l0 Eq. inversions Eq. assumption.
  (* step: subsumption *)
  + intros x l Eq. subst. specialize (IHTy _ _ eq_refl).
    apply invert_var_has_fld in IHTy.
    destruct IHTy as [X [Ds [T' [Tyx [Exp [Has Eq]]]]]].
    (*
    assert Tyx': ty_trm G (trm_var (avar_f x)) (ty_or X (typ_bind (dec_fld U)))
      by subsumption
    then the expansion of (ty_or X (typ_bind (dec_fld U))) has (dec_fld (t_or T U))
    since T <: U, (t_or T U) is kind of the same as U <-- but not enough!
    *)
Abort.

Lemma invert_ty_sel: forall G t l T,
  ty_trm G (trm_sel t l) T ->
  has G t (label_fld l) (dec_fld T).
Proof.
  introv Ty. gen_eq t0: (trm_sel t l). gen t l.
  induction Ty; intros t' l' Eq; try (solve [ discriminate ]).
  + inversions Eq. assumption.
  + subst. rename t' into t, l' into l. specialize (IHTy _ _ eq_refl).
    inversions IHTy.
    - apply has_trm with T0 Ds. (* requires imprecise expansion *)
Abort.

Lemma invert_ty_sel: forall G t l T,
  ty_trm G (trm_sel t l) T ->
  exists T', subtyp oktrans G T' T /\ has G t (label_fld l) (dec_fld T').
Proof.
  introv Ty. gen_eq t0: (trm_sel t l). gen t l.
  induction Ty; intros t' l' Eq; try (solve [ discriminate ]).
  + inversions Eq. exists T. auto.
  + subst. rename t' into t, l' into l. specialize (IHTy _ _ eq_refl).
    destruct IHTy as [T' [St Has]]. exists T'. split.
    - apply subtyp_trans with T; assumption.
    - exact Has.
Qed.

Lemma invert_ty_call: forall G t m V u,
  ty_trm G (trm_call t m u) V ->
  exists U, has G t (label_mtd m) (dec_mtd U V) /\ ty_trm G u U.
Proof.
  introv Ty. gen_eq e: (trm_call t m u). gen t m u.
  induction Ty; intros t0 m0 u0 Eq; try solve [ discriminate ]; symmetry in Eq.
  + (* case ty_call *)
    inversions Eq. exists U. auto.
  + (* case ty_sbsm *)
    subst t. specialize (IHTy _ _ _ eq_refl).
    (* need to turn (dec_mtd U0 T) into (dec_mtd U0 U) using T <: U, but there's
       no subsumption in has, so we would need to do the subsumption when
       typing t0 --> tricky *)
Abort.

Lemma invert_ty_call: forall G t m V u,
  ty_trm G (trm_call t m u) V ->
  exists U, has G t (label_mtd m) (dec_mtd U V) /\ ty_trm G u U.
Proof.
  intros. inversions H.
  + eauto.
  + admit. (* subsumption case *)
Qed. (* TODO we don't want to depend on this! *)

Lemma invert_ty_new: forall G ds T1 T2,
  ty_trm G (trm_new T1 ds) T2 ->
  subtyp oktrans G T1 T2 /\
  exists L Ds, exp G T1 Ds /\
               (forall x, x \notin L ->
                  ty_defs (G & x ~ T1) (open_defs x ds) (open_decs x Ds)) /\
               (forall x, x \notin L ->
                  forall M S U, decs_has (open_decs x Ds) M (dec_typ S U) ->
                               subtyp oktrans (G & x ~ T1) S U).
Proof.
  introv Ty. gen_eq t0: (trm_new T1 ds). gen T1 ds.
  induction Ty; intros T1' ds' Eq; try (solve [ discriminate ]); symmetry in Eq.
  + (* case ty_new *)
    inversions Eq. apply (conj (subtyp_mode (subtyp_refl _ _))).
    exists L Ds. auto.
  + (* case ty_sbsm *)
    subst. rename T1' into T1, T into T2, ds' into ds. specialize (IHTy _ _ eq_refl).
    destruct IHTy as [St IHTy].
    apply (conj (subtyp_trans St H) IHTy).
Qed.

Lemma invert_subtyp_bind: forall G Ds1 Ds2,
  subtyp oktrans G (typ_bind Ds1) (typ_bind Ds2) ->
  exists L, forall z : var, z \notin L ->
    subdecs oktrans (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds2).
Proof.
Abort.

Lemma invert_wf_sto_with_weakening: forall s G,
  wf_sto s G ->
  forall x ds T T',
    binds x (object T ds) s -> 
    binds x T' G 
    -> T' = T 
    /\ exists Ds, exp G T Ds /\
                  ty_defs G (open_defs x ds) (open_decs x Ds) /\
                  (forall L S U, decs_has (open_decs x Ds) L (dec_typ S U) -> 
                                 subtyp notrans G S U).
Proof.
  introv Wf Bs BG.
  lets P: (invert_wf_sto Wf).
  specialize (P x ds T T' Bs BG).
  destruct P as [EqT [G1 [G2 [Ds [EqG [Exp [Ty F]]]]]]]. subst.
  apply (conj eq_refl).
  exists Ds. lets Ok: (wf_sto_to_ok_G Wf).
  refine (conj _ (conj _ _)).
  + rewrite <- concat_assoc. 
    apply (weaken_exp_end Exp).
    rewrite concat_assoc. exact Ok.
  + apply (weaken_ty_defs Ty Ok).
  + intros L S U Has. specialize (F L S U Has). apply (subtyp_weaken_end Ok F).
Qed.

Lemma invert_wf_sto_with_sbsm: forall s G,
  wf_sto s G ->
  forall x ds T T', 
    binds x (object T ds) s ->
    ty_trm G (trm_var (avar_f x)) T' (* <- instead of binds *)
    -> subtyp oktrans G T T'
    /\ exists Ds, exp G T Ds /\
                  ty_defs G (open_defs x ds) (open_decs x Ds) /\
                  (forall L S U, decs_has (open_decs x Ds) L (dec_typ S U) -> 
                                 subtyp notrans G S U).
Proof.
  introv Wf Bis Tyx.
  apply invert_ty_var in Tyx. destruct Tyx as [T'' [St BiG]].
  destruct (invert_wf_sto_with_weakening Wf Bis BiG) as [EqT [Ds [Exp [Tyds F]]]].
  subst T''.
  lets Ok: (wf_sto_to_ok_G Wf).
  apply (conj St).
  exists Ds. auto.
Qed.


(* ###################################################################### *)

Lemma subtyp_preserves_empty_exp: forall G T U,
  exp G T decs_nil ->
  subtyp oktrans G T U ->
  exp G U decs_nil.
Proof.
  introv Exp. gen_eq Ds: decs_nil. gen U. induction Exp; introv Eq St.
  + 
Abort.

Lemma exp_supertyp_of_top: forall G T,
  subtyp oktrans G typ_top T ->
  exp G T decs_nil.
Proof.
  introv St. gen_eq U: typ_top. induction St.
  + (* case subtyp_refl *)     intro. subst. auto.
  + (* case subtyp_top *)      intro. subst. auto.
  + (* case subtyp_bot *)      intro. subst. discriminate.
  + (* case subtyp_bind *)     intro. subst. discriminate.
  + (* case subtyp_sel_l *)    intro. subst. discriminate.
  + (* case subtyp_sel_r *)
    intro. subst.
    admit.
  + (* case subtyp_mode *)
    admit.
  + (* case subtyp_trans *)
    admit.
Qed.

Lemma exp_preserves_sub: forall m G T1 T2,
  subtyp m G T1 T2 ->
  forall x Ds1 Ds2,
  ok G ->
  binds x T1 G ->
  exp G T1 Ds1 ->
  exp G T2 Ds2 ->
  subdecs oktrans G (open_decs x Ds1) (open_decs x Ds2).
Proof.
  introv St.
    induction St; 
    try rename Ds1 into weirdDs1; try rename Ds2 into weirdDs2; try rename x into z;
    intros x Ds1 Ds2 Ok Bi Exp1 Exp2.
  + (* case subtyp_refl *)
    assert (Eq: Ds1 = Ds2) by apply (exp_unique Exp1 Exp2).
    subst. apply subdecs_refl.
  + (* case subtyp_top *)
    subst. inversions Exp2. unfold open_decs, open_rec_decs. apply subdecs_empty.
  + (* case subtyp_bot *)
    inversions Exp1.
  + (* case subtyp_bind *)
    inversions Exp1. inversions Exp2.
    pick_fresh z. assert (zL: z \notin L) by auto. specialize (H z zL).
    assert (Ok': ok (G & z ~ typ_bind Ds1)) by auto.
    lets P: (@subdecs_subst_principle oktrans G z x (typ_bind Ds1) 
      (open_decs z Ds1) (open_decs z Ds2) Ok' H Bi).
    assert (zDs1: z \notin fv_decs Ds1) by auto.
    assert (zDs2: z \notin fv_decs Ds2) by auto.
    rewrite <- (@subst_intro_decs z x Ds1 zDs1) in P.
    rewrite <- (@subst_intro_decs z x Ds2 zDs2) in P.
    apply P.
  + (* case subtyp_sel_l *)
    inversions Exp1. lets Eq: (phas_unique H H3). inversions Eq.
    apply IHSt.
    - exact Ok.
    - admit. (* doesn't hold!!!! *)
    - assumption.
    - assumption.
  + (* case subtyp_sel_r *)
    inversions Exp2. lets Eq: (phas_unique H H3). inversions Eq.
    admit.
  + (* case subtyp_mode *)
    apply* IHSt.
  + (* case subtyp_trans *)
    rename Ds2 into Ds3. rename Exp2 into Exp3.
    assert (Exp2: exists Ds2, exp G T2 Ds2) by admit. (* only in realizable env! *)
    destruct Exp2 as [Ds2 Exp2].
    specialize (IHSt1 _ _ _ Ok Bi Exp1 Exp2).
    (*
    specialize (IHSt2 _ _ _ Ok ??? Exp2 Exp3).
    apply (subtyp_trans IHSt1 IHSt2).
    *)
Abort.

(* * typ_top and typ_bind have a trivial expansion
   * typ_bot has no expansion
   * for typ_sel, we prove a lemma: *)

Lemma typ_sel_expands: forall s G v L Lo Hi,
  wf_sto s G -> (* to get Lo<:Hi *)
  phas G v L (dec_typ Lo Hi) ->
  exists Ds, exp G (typ_sel (pth_var (avar_f v)) L) Ds.
Abort. (* does not hold if Hi is Bot, which can even be the case in realizable envs *)

Lemma typ_sel_expands: forall s G v L Lo Hi,
  wf_sto s G -> (* to get Lo<:Hi *)
  ~ subtyp oktrans G Hi typ_bot ->
  phas G v L (dec_typ Lo Hi) ->
  exists Ds, exp G (typ_sel (pth_var (avar_f v)) L) Ds.
Proof.
  introv Wf. gen v L Lo Hi. induction Wf; introv Not Has.
  + inversions Has. false (binds_empty_inv H0).
  + inversion Has. subst.
    lets Ok: (wf_sto_to_ok_G Wf). assert (Ok': ok (G & x ~ T)) by auto.
    destruct D as [Lo' Hi' | T' | U V];
      unfold open_dec, open_rec_dec in H4; try discriminate.
    fold open_rec_typ in H4. inversions H4.
    apply binds_push_inv in H5. destruct H5 as [[Eq1 Eq2] | [Ne Bi]].
    - subst. apply (decs_has_open x) in H10.
      unfold open_dec, open_rec_dec in H10. fold open_rec_typ in H10.
      destruct Hi' as [ | | Ds2 | y M].
      * exists decs_nil. apply (exp_sel Has). simpl. apply exp_top.
      * false. apply Not. simpl. apply subtyp_mode. apply subtyp_bot.
      * exists (open_rec_decs 1 x Ds2). apply (exp_sel Has). simpl. apply exp_bind.
      * admit. (* TODO induction doesn't work because we y might be avar_b so 
        y = x, i.e. upper bound of x.L is x.M and we cannot remove x from the
        ctx/sto
        ---> how can we prevent cycles like x.L: Bot .. x.M // x.M: Bot .. x.L ?? *)
    - assert (Not': ~ subtyp oktrans G (open_typ v Hi') typ_bot). {
        intro St. apply Not.
        apply (subtyp_weaken_end Ok' St).
      }
      assert (Has': phas G v L (open_dec v (dec_typ Lo' Hi'))). {
        apply phas_var with T0 Ds0.
        - assumption.
        - assert (Impl: binds v T0 G -> exp (G & x ~ T) T0 Ds0 -> exp G T0 Ds0) by admit.
          apply* Impl.
        - assumption.
      }
      specialize (IHWf v L (open_typ v Lo') (open_typ v Hi') Not' Has').
      destruct IHWf as [Ds1 IH]. exists Ds1. apply (weaken_exp_end IH Ok').
Qed.

Lemma exp_preserves_sub: forall m G T1 T2 s Ds1 Ds2,
  subtyp m G T1 T2 ->
  wf_sto s G ->
  exp G T1 Ds1 ->
  exp G T2 Ds2 ->
  exists L, forall z : var, z \notin L ->
    subdecs oktrans (G & z ~ typ_bind Ds1) (open_decs z Ds1) (open_decs z Ds2).
Proof.
  introv St. gen s Ds1 Ds2.
  induction St; introv Wf Exp1 Exp2; lets Ok: (wf_sto_to_ok_G Wf).
  + (* case subtyp_refl *)
    assert (Eq: Ds1 = Ds2) by apply (exp_unique Exp1 Exp2).
    subst. exists vars_empty. intros. apply subdecs_refl.
  + (* case subtyp_top *)
    subst. inversions Exp2. exists vars_empty. intros.
    unfold open_decs, open_rec_decs. apply subdecs_empty.
  + (* case subtyp_bot *)
    inversions Exp1.
  + (* case subtyp_bind *)
    inversions Exp1. inversions Exp2. exists L. exact H.
  + (* case subtyp_sel_l *)
    inversions Exp1. lets Eq: (phas_unique H H3). inversions Eq.
    specialize (IHSt s Ds1 Ds2 Wf H5 Exp2).
    destruct IHSt as [L0 IHSt]. exists L0. intros z zL0. specialize (IHSt z zL0).
    apply IHSt; assumption.
  + (* case subtyp_sel_r *)
    inversions Exp2. lets Eq: (phas_unique H H3). inversions Eq.
    assert (Exp: exists Ds, exp G Lo Ds) by admit.
    destruct Exp as [Ds Exp].
    specialize (IHSt1 s Ds  Ds2 Wf Exp  H5 ). destruct IHSt1 as [L1 IHSt1]. 
    specialize (IHSt2 s Ds1 Ds  Wf Exp1 Exp). destruct IHSt2 as [L2 IHSt2].
    exists (L1 \u L2 \u dom G). intros z zL1L2.
    auto_specialize.
    assert (Ok': ok (G & z ~ typ_bind Ds)) by auto.
    lets IHSt1': (subdecs_narrow_last Ok' IHSt1 IHSt2).
    apply (subdecs_trans_oktrans IHSt2 IHSt1').
  + (* case subtyp_mode *)
    apply* IHSt.
  + (* case subtyp_trans *)
    rename Ds2 into Ds3. rename Exp2 into Exp3.
    assert (Exp2: exists Ds2, exp G T2 Ds2) by admit. (* only in realizable env! *)
    destruct Exp2 as [Ds2 Exp2].
    specialize (IHSt1 _ _ _ Wf Exp1 Exp2). destruct IHSt1 as [L1 IHSt1].
    specialize (IHSt2 _ _ _ Wf Exp2 Exp3). destruct IHSt2 as [L2 IHSt2].
    exists (L1 \u L2 \u dom G). intros z zL1L2.
    auto_specialize.
    assert (Ok': ok (G & z ~ typ_bind Ds2)) by auto.
    lets IHSt2': (subdecs_narrow_last Ok' IHSt2 IHSt1).
    apply (subdecs_trans_oktrans IHSt1 IHSt2').
Qed.

Print Assumptions exp_preserves_sub.

Lemma exp_preserves_sub1: forall m G T1 T2 Ds1 Ds2,
  subtyp m G T1 T2 ->
  exp G T1 Ds1 ->
  exp G T2 Ds2 ->
  subtyp oktrans G (typ_bind Ds1) (typ_bind Ds2).
Proof.
  introv St. gen Ds1 Ds2. induction St; introv Exp1 Exp2.
  + (* case subtyp_refl *)
    assert (Eq: Ds1 = Ds2) by apply (exp_unique Exp1 Exp2).
    subst. apply subtyp_mode. apply subtyp_refl.
  + (* case subtyp_top *)
    subst. inversions Exp2. apply subtyp_mode. apply subtyp_bind with \{}. intros. 
    unfold open_decs, open_rec_decs. apply subdecs_empty.
  + (* case subtyp_bot *)
    inversions Exp1.
  + (* case subtyp_bind *)
    inversions Exp1. inversions Exp2. apply subtyp_mode. apply (subtyp_bind _ H).
  + (* case subtyp_sel_l *)
    inversions Exp1. lets Eq: (phas_unique H H3). inversions Eq.
    apply IHSt; assumption.
  + (* case subtyp_sel_r *)
    inversions Exp2. lets Eq: (phas_unique H H3). inversions Eq.
    admit.
  + (* case subtyp_mode *)
    apply* IHSt.
  + (* case subtyp_trans *)
    rename Ds2 into Ds3. rename Exp2 into Exp3.
    assert (Exp2: exists Ds2, exp G T2 Ds2) by admit. (* only in realizable env! *)
    destruct Exp2 as [Ds2 Exp2].
    specialize (IHSt1 _ _ Exp1 Exp2).
    specialize (IHSt2 _ _ Exp2 Exp3).
    apply (subtyp_trans IHSt1 IHSt2).
Qed.

(*
Lemma exp_preserves_sub: forall m G T1 T2, subtyp m G T1 T2 -> forall Ds1 Ds2,
  exp G T1 Ds1 ->
  exp G T2 Ds2 ->
  subdecs m G Ds1 Ds2.
Proof.
  apply (subtyp_ind (fun m G T1 T2 => forall Ds1 Ds2,
    exp G T1 Ds1 ->
    exp G T2 Ds2 ->
    subdecs m G Ds1 Ds2)). intros.

  introv St. gen Ds1 Ds2. gen induction St; intros Ds1' Ds2' Exp1 Exp2. ; try discriminate.
  refine (subtyp_ind _ _ _ _  _ _ _ _ _). intros.

Lemma exp_preserves_sub: forall G T1 T2 Ds1 Ds2,
  subtyp oktrans G T1 T2 ->
  exp G T1 Ds1 ->
  exp G T2 Ds2 ->
  subdecs oktrans G Ds1 Ds2.
Proof.
  introv St Exp1. gen St. gen T2 Ds2. induction Exp1.
  + introv St Exp2. 

Lemma exp_and_phas_preserves_sub:
   (forall G T1 Ds1, exp G T1 Ds1 -> forall T2 Ds1 Ds2,
      subtyp oktrans G T1 T2 ->
      exp G T2 Ds2 ->
      subdecs oktrans G Ds1 Ds2)
/\ (forall G v l D, phas G v l D -> forall 

*)
Lemma exp_preserves_sub2: forall G T1 T2 Ds1 Ds2,
  subtyp oktrans G T1 T2 ->
  exp G T1 Ds1 ->
  exp G T2 Ds2 ->
  subdecs oktrans G Ds1 Ds2.
Admitted. (* TODO does not hold (need to open Ds1 and Ds2! *)

Lemma precise_decs_subdecs_of_imprecise_decs: forall s G x ds X1 X2 Ds1 Ds2, 
  wf_sto s G ->
  binds x (object X1 ds) s ->
  ty_trm G (trm_var (avar_f x)) X2 ->
  exp G X1 Ds1 ->
  exp G X2 Ds2 ->
  subdecs oktrans G (open_decs x Ds1) (open_decs x Ds2).
Proof.
  introv Wf Bis Tyx Exp1 Exp2.
  lets Ok: (wf_sto_to_ok_G Wf).
  destruct (invert_wf_sto_with_sbsm Wf Bis Tyx) as [St _].
  lets Sds: (exp_preserves_sub St Wf Exp1 Exp2).
  destruct Sds as [L Sds].
  pick_fresh z. assert (zL: z \notin L) by auto. specialize (Sds z zL).
  lets BiG: (sto_binds_to_ctx_binds Wf Bis).
  assert (Sds': subdecs oktrans (G & z ~ X1) (open_decs z Ds1) (open_decs z Ds2))
    by admit. (* narrowing to type X1 (which expands) *)
  assert (Ok': ok (G & z ~ X1)) by auto.
  lets P: (@subdecs_subst_principle oktrans _ z x X1 
              (open_decs z Ds1) (open_decs z Ds2) Ok' Sds' BiG).
  assert (zDs1: z \notin fv_decs Ds1) by auto.
  assert (zDs2: z \notin fv_decs Ds2) by auto.
  rewrite <- (@subst_intro_decs z x Ds1 zDs1) in P.
  rewrite <- (@subst_intro_decs z x Ds2 zDs2) in P.
  exact P.
Qed.

Lemma ty_def_sbsm: forall G d D1 D2,
  ty_def G d D1 ->
  subdec oktrans G D1 D2 ->
  ty_def G d D2.
Proof.
  introv Ty Sd. destruct Ty; inversion Sd; try discriminate; subst; clear Sd.
  + apply ty_typ.
  + apply ty_typ.
  + apply (ty_fld H).
  + apply (ty_fld (ty_sbsm H H3)).
  + apply (ty_mtd _ H).
  + apply ty_mtd with L. intros x xL. specialize (H x xL).
    (* again, we need narrowing, but this time, S2 might even be unrealizable! *)
Abort.

Lemma has_sound: forall s G x X1 ds l D2,
  wf_sto s G ->
  binds x (object X1 ds) s ->
  has G (trm_var (avar_f x)) l D2 ->
  exists Ds1 D1,
    ty_defs G (open_defs x ds) (open_decs x Ds1) /\
    decs_has (open_decs x Ds1) l D1 /\
    subdec oktrans G D1 D2.
Proof.
  introv Wf Bis Has.
  apply invert_var_has_dec in Has.
  destruct Has as [X2 [Ds2 [T [Tyx [Exp2 [Ds2Has Eq]]]]]]. subst.
  destruct (invert_wf_sto_with_sbsm Wf Bis Tyx) as [St [Ds1 [Exp1 [Tyds _]]]].
  lets Sds: (precise_decs_subdecs_of_imprecise_decs Wf Bis Tyx Exp1 Exp2).
  apply (decs_has_open x) in Ds2Has.
  destruct (decs_has_preserves_sub Ds2Has Sds) as [D1 [Ds1Has Sd]].
  exists Ds1 D1.
  apply (conj Tyds (conj Ds1Has Sd)).
Qed.

(*


wf_sto s G
has G (trm_var (avar_f x)) l D2
______________________________________
binds x (object X1 ds) s
ty_defs G (open_defs x ds) (open_decs x Ds1)
decs_has Ds1 l D1
subdec oktrans G D1 D2


wf_sto s G
binds x (object X1 ds) s
ty_trm G (trm_var (avar_f x)) X2
exp G X1 Ds1
exp G X2 Ds2
______________________________________
subdecs oktrans G (open_decs x Ds1) (open_decs x Ds2)


subtyp oktrans G X1 X2
exp G X1 Ds1
exp G X2 Ds2
______________________________________
subdecs oktrans G (open_decs x Ds1) (open_decs x Ds2)  <-- where does x come from??


Lemma has_sound: forall,
  has G (trm_var (avar_f x)) l D ->
  binds x (object T ds) s ->
  wf_sto s G ->
  exists Ds d,
    exp G T Ds /\
    ty_defs G (open_defs x ds) (open_decs x Ds) /\
    ty_def G (open_def x d) (open_dec x D) /\
    decs_has (open_decs x Ds) l D /\
    defs_has (open_defs x ds) l d
dsHas


Bis : binds x (object Tds ds) s
Wf : wf_sto s G
Has : has G (trm_var (avar_f x)) l D
______________________________________
Tyd : ty_def (G1 & x ~ X') (open_def x d) (open_decs x DX')
DsHas : decs_has (open_decs x DsX') l D
dsHas


Bis : binds x (object Tds ds) s
Wf : wf_sto s G
Has : has G (trm_var (avar_f x)) l D
______________________________________
Tyds : ty_defs (G1 & x ~ X') (open_defs x ds) (open_decs x DsX')
Has' : decs_has (open_decs x DsX') l D



Bis : binds x (object Tds ds) s
Wf : wf_sto s G
Has : has G (trm_var (avar_f x)) (label_fld l) (dec_fld T)
______________________________________
Tyds : ty_defs (G1 & x ~ X') (open_defs x ds) (open_decs x DsX')
Has' : decs_has (open_decs x DsX') (label_fld l) D

*)


(* ###################################################################### *)
(* ###################################################################### *)
(** * Soundness Proofs *)

(* ###################################################################### *)
(** ** Progress *)

Theorem progress_result: progress.
Proof.
  introv Wf Ty. gen G e T Ty s Wf.
  set (progress_for := fun s e =>
                         (exists e' s', red e s e' s') \/
                         (exists x o, e = (trm_var (avar_f x)) /\ binds x o s)).
  apply (ty_has_mutind
    (fun G e l d (Hhas: has G e l d)  => forall s, wf_sto s G -> progress_for s e)
    (fun G e T   (Hty:  ty_trm G e T) => forall s, wf_sto s G -> progress_for s e));
    unfold progress_for; clear progress_for.
  (* case has_trm *)
  + intros. auto.
  (* case has_var *)
  + intros G v T Ds l D Ty IH Exp Has s Wf.
    right. apply invert_ty_var in Ty. destruct Ty as [T' [St BiG]].
    destruct (ctx_binds_to_sto_binds Wf BiG) as [o Bis].
    exists v o. auto.
  (* case ty_var *)
  + intros G x T BiG s Wf.
    right. destruct (ctx_binds_to_sto_binds Wf BiG) as [o Bis].
    exists x o. auto.
  (* case ty_sel *)
  + intros G t l T Has IH s Wf.
    left. specialize (IH s Wf). destruct IH as [IH | IH].
    (* receiver is an expression *)
    - destruct IH as [s' [e' IH]]. do 2 eexists. apply (red_sel1 l IH). 
    (* receiver is a var *)
    - destruct IH as [x [[X1 ds] [Eq Bis]]]. subst.
      lets P: (has_sound Wf Bis Has).
      destruct P as [Ds1 [D1 [Tyds [Ds1Has Sd]]]].
      destruct (decs_has_to_defs_has Tyds Ds1Has) as [d dsHas].
      destruct (defs_has_fld_sync dsHas) as [r Eqd]. subst.
      exists (trm_var r) s.
      apply (red_sel Bis dsHas).
  (* case ty_call *)
  + intros G t m U V u Has IHrec Tyu IHarg s Wf. left.
    specialize (IHrec s Wf). destruct IHrec as [IHrec | IHrec].
    - (* case receiver is an expression *)
      destruct IHrec as [s' [e' IHrec]]. do 2 eexists. apply (red_call1 m _ IHrec).
    - (* case receiver is  a var *)
      destruct IHrec as [x [[Tds ds] [Eq Bis]]]. subst.
      specialize (IHarg s Wf). destruct IHarg as [IHarg | IHarg].
      (* arg is an expression *)
      * destruct IHarg as [s' [e' IHarg]]. do 2 eexists. apply (red_call2 x m IHarg).
      (* arg is a var *)
      * destruct IHarg as [y [o [Eq Bisy]]]. subst.
        lets P: (has_sound Wf Bis Has).
        destruct P as [Ds1 [D1 [Tyds [Ds1Has Sd]]]].
        destruct (decs_has_to_defs_has Tyds Ds1Has) as [d dsHas].
        destruct (defs_has_mtd_sync dsHas) as [body Eqd]. subst.
        exists (open_trm y body) s.
        apply (red_call y Bis dsHas).
  (* case ty_new *)
  + intros L G T ds Ds Exp Tyds F s Wf.
    left. pick_fresh x.
    exists (trm_var (avar_f x)) (s & x ~ (object T ds)).
    apply* red_new.
  (* case ty_sbsm *)
  + intros. auto_specialize. assumption.
Qed.

Print Assumptions progress_result.

(*
Lemma ty_open_trm_change_var: forall x y G e S T,
  ok (G & x ~ S) ->
  ok (G & y ~ S) ->
  x \notin fv_trm e ->
  ty_trm (G & x ~ S) (open_trm x e) T ->
  ty_trm (G & y ~ S) (open_trm y e) T.
Proof.
  introv Hokx Hoky xFr Ty.
  destruct (classicT (x = y)) as [Eq | Ne]. subst. assumption.
  assert (Hokxy: ok (G & x ~ S & y ~ S)) by destruct* (ok_push_inv Hoky).
  assert (Ty': ty_trm (G & x ~ S & y ~ S) (open_trm x e) T).
  apply (weaken_ty_trm Ty Hokxy).
  rewrite* (@subst_intro_trm x y e).
  lets Bi: (binds_push_eq y S G).
  destruct (trm_subst_principles y S) as [_ [P _]].
  apply (P _ (open_trm x e) T Ty' G (y ~ S) x eq_refl Bi Hokxy).
Qed.
*)

Lemma ty_open_defs_change_var: forall x y G ds Ds S,
  ok (G & x ~ S) ->
  ok (G & y ~ S) ->
  x \notin fv_defs ds ->
  x \notin fv_decs Ds ->
  ty_defs (G & x ~ S) (open_defs x ds) (open_decs x Ds) ->
  ty_defs (G & y ~ S) (open_defs y ds) (open_decs y Ds).
Proof.
  introv Okx Oky Frds FrDs Ty.
  destruct (classicT (x = y)) as [Eq | Ne].
  + subst. assumption.
  + assert (Okyx: ok (G & y ~ S & x ~ S)) by destruct* (ok_push_inv Okx).
    assert (Ty': ty_defs (G & y ~ S & x ~ S) (open_defs x ds) (open_decs x Ds))
      by apply (weaken_ty_defs_middle Ty Okyx).
    rewrite* (@subst_intro_defs x y ds).
    rewrite* (@subst_intro_decs x y Ds).
    lets Biy: (binds_push_eq y S G).
    destruct (trm_subst_principles y S) as [_ [_ [_ P]]].
    specialize (P _ _ _ Ty' (G & y ~ S) empty x).
    rewrite concat_empty_r in P.
    specialize (P eq_refl Biy Okyx).
    unfold subst_ctx in P. rewrite map_empty in P. rewrite concat_empty_r in P.
    exact P.
Qed.


(* ###################################################################### *)
(** ** Preservation *)

Theorem preservation_proof:
  forall e s e' s' (Hred: red e s e' s') G T (Hwf: wf_sto s G) (Hty: ty_trm G e T),
  (exists H, wf_sto s' (G & H) /\ ty_trm (G & H) e' T).
Proof.
  intros s e s' e' Red. induction Red.
  (* red_call *)
  + intros G U2 Wf TyCall. rename H into Bis, H0 into dsHas, T into X1.
    exists (@empty typ). rewrite concat_empty_r. apply (conj Wf).
    apply invert_ty_call in TyCall.
    destruct TyCall as [T2 [Has Tyy]].
    lets P: (has_sound Wf Bis Has).
    destruct P as [Ds1 [D1 [Tyds [Ds1Has Sd]]]].
    apply invert_subdec_mtd_sync_left in Sd.
    destruct Sd as [T1 [U1 [Eq [StT StU]]]]. subst D1.
    destruct (invert_ty_mtd_inside_ty_defs Tyds dsHas Ds1Has) as [L0 Tybody].
    apply invert_ty_var in Tyy.
    destruct Tyy as [T3 [StT3 Biy]].
    pick_fresh y'.
    rewrite* (@subst_intro_trm y' y body).
    assert (Fry': y' \notin fv_typ U2) by auto.
    assert (Eqsubst: (subst_typ y' y U2) = U2)
      by apply* subst_fresh_typ_dec_decs.
    rewrite <- Eqsubst.
    lets Ok: (wf_sto_to_ok_G Wf).
    apply (@trm_subst_principle G y' y (open_trm y' body) T3 _).
    - auto.
    - assert (y'L0: y' \notin L0) by auto. specialize (Tybody y' y'L0).
      apply ty_sbsm with U1.
      * assert (subtyp oktrans G T3 T1 ->
                ty_trm (G & y' ~ T1) (open_trm y' body) U1 ->
                ty_trm (G & y' ~ T3) (open_trm y' body) U1)
           by admit. (* narrowing *)
        refine (H _ Tybody).
        apply (subtyp_trans StT3 StT).
      * apply subtyp_weaken_end. auto. apply StU.
    - exact Biy.
  (* red_sel *)
  + intros G T3 Wf TySel. rename H into Bis, H0 into dsHas.
    exists (@empty typ). rewrite concat_empty_r. apply (conj Wf).
    apply invert_ty_sel in TySel.
    destruct TySel as [T2 [StT23 Has]].
    lets P: (has_sound Wf Bis Has).
    destruct P as [Ds1 [D1 [Tyds [Ds1Has Sd]]]].
    apply invert_subdec_fld_sync_left in Sd.
    destruct Sd as [T1 [Eq StT12]]. subst D1.
    refine (ty_sbsm _ StT23).
    refine (ty_sbsm _ StT12).
    apply (invert_ty_fld_inside_ty_defs Tyds dsHas Ds1Has).
  (* red_new *)
  + rename T into T1. intros G T2 Wf Ty.
    apply invert_ty_new in Ty.
    destruct Ty as [StT12 [L [Ds [Exp [Tyds F]]]]].
    exists (x ~ T1).
    pick_fresh x'. assert (Frx': x' \notin L) by auto.
    specialize (Tyds x' Frx').
    specialize (F x' Frx').
    assert (xG: x # G) by apply* sto_unbound_to_ctx_unbound.
    split.
    - apply (wf_sto_push _ Wf H xG Exp).
      * apply* (@ty_open_defs_change_var x').
      * intros M S U dsHas. specialize (F M S U). admit. (* meh TODO *)
    - lets Ok: (wf_sto_to_ok_G Wf). assert (Okx: ok (G & x ~ T1)) by auto.
      apply (subtyp_weaken_end Okx) in StT12.
      refine (ty_sbsm _ StT12). apply ty_var. apply binds_push_eq.
  (* red_call1 *)
  + intros G Tr Wf Ty.
    apply invert_ty_call in Ty.
    destruct Ty as [Ta [Has Tya]].
    apply invert_has in Has.
    destruct Has as [Has | Has].
    - (* case has_trm *)
      destruct Has as [To [Ds [Tyo [Exp [DsHas Clo]]]]].
      specialize (IHRed G To Wf Tyo). destruct IHRed as [H [Wf' Tyo']].
      lets Ok: (wf_sto_to_ok_G Wf').
      exists H. apply (conj Wf'). apply (@ty_call (G & H) o' m Ta Tr a).
      * refine (has_trm Tyo' _ DsHas Clo).
        apply (weaken_exp_end Exp Ok).
      * apply (weaken_ty_trm Tya Ok).
    - (* case has_var *)
      destruct Has as [x [Tx [Ds [D' [Eqx _]]]]]. subst.
      inversion Red. (* contradiction: vars don't step *)
  (* red_call2 *)
  + intros G Tr Wf Ty.
    apply invert_ty_call in Ty.
    destruct Ty as [Ta [Has Tya]].
    specialize (IHRed G Ta Wf Tya).
    destruct IHRed as [H [Wf' Tya']].
    exists H. apply (conj Wf'). apply (@ty_call (G & H) _ m Ta Tr a').
    - lets Ok: wf_sto_to_ok_G Wf'.
      apply (weaken_has Has Ok).
    - assumption.
  (* red_sel1 *)
  + intros G T2 Wf TySel.
    apply invert_ty_sel in TySel.
    destruct TySel as [T1 [St Has]].
    apply invert_has in Has.
    destruct Has as [Has | Has].
    - (* case has_trm *)
      destruct Has as [To [Ds [Tyo [Exp [DsHas Clo]]]]].
      specialize (IHRed G To Wf Tyo). destruct IHRed as [H [Wf' Tyo']].
      lets Ok: (wf_sto_to_ok_G Wf').
      exists H. apply (conj Wf').
      apply (subtyp_weaken_end Ok) in St.
      refine (ty_sbsm _ St). apply (@ty_sel (G & H) o' l T1).
      refine (has_trm Tyo' _ DsHas Clo).
      apply (weaken_exp_end Exp Ok).
    - (* case has_var *)
      destruct Has as [x [Tx [Ds [D' [Eqx _]]]]]. subst.
      inversion Red. (* contradiction: vars don't step *)
Qed.

Theorem preservation_result: preservation.
Proof.
  introv Hwf Hty Hred.
  destruct (preservation_proof Hred Hwf Hty) as [H [Hwf' Hty']].
  exists (G & H). split; assumption.
Qed.

Print Assumptions preservation_result.
