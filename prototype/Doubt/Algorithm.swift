/// The free monad over `Operation`, implementing the language of diffing.
///
/// As with `Free`, this is “free” in the sense of “unconstrained,” i.e. “the monad induced by `Operation` without extra assumptions.”
///
/// Where `Operation` models a single diffing strategy, `Algorithm` models the recursive selection of diffing strategies at each node. Thus, a value in `Algorithm` models an algorithm for constructing a value in the type `Result` from the resulting diffs. By this means, diffing can be adapted not just to the specific grammar, but to specific trees produced by that grammar, and even the values of type `A` encapsulated at each node.
public enum Algorithm<Term: TermType, Result> {
	/// The type of `Patch`es produced by `Algorithm`s.
	public typealias Patch = Doubt.Patch<Term>

	/// The type of `Diff`s which `Algorithm`s produce.
	public typealias Diff = Free<Term.LeafType, Patch>

	/// The injection of a value of type `Result` into an `Operation`.
	///
	/// Equally, a way to return a result or throw an error during computation, as determined by the type which `Result` is instantiated to, and the specific context in which it is being evaluated.
	case Pure(Result)

	/// A recursive instantiation of `Operation`, unrolling another iteration of the recursive type.
	indirect case Roll(Operation<Algorithm, Term, Diff>)

	public func analysis<C>(@noescape ifPure ifPure: Result -> C, @noescape ifRoll: Operation<Algorithm, Term, Diff> -> C) -> C {
		switch self {
		case let .Pure(b):
			return ifPure(b)
		case let .Roll(a):
			return ifRoll(a)
		}
	}


	// MARK: Functor

	public func map<Other>(transform: Result -> Other) -> Algorithm<Term, Other> {
		return analysis(ifPure: transform >>> Algorithm<Term, Other>.Pure, ifRoll: { .Roll($0.map { $0.map(transform) }) })
	}


	// MARK: Monad

	public func flatMap<C>(transform: Result -> Algorithm<Term, C>) -> Algorithm<Term, C> {
		return analysis(ifPure: transform, ifRoll: { .Roll($0.map { $0.flatMap(transform) }) })
	}


	/// Evaluates the encoded algorithm, returning its result.
	public func evaluate(equals: (Term, Term) -> Bool, recur: (Term, Term) -> Diff?) -> Result {
		let recur = {
			equals($0, $1)
				? Diff($1)
				: recur($0, $1)
		}
		let recurOrReplace = {
			recur($0, $1) ?? .Pure(.Replace($0, $1))
		}
		func cost(diff: Diff) -> Int {
			return diff.map { abs(($0.state.before?.size ?? 0) - ($0.state.after?.size ?? 0)) }.iterate { syntax in
				switch syntax {
				case .Leaf:
					return 0
				case let .Indexed(costs):
					return costs.reduce(0, combine: +)
				case let .Keyed(costs):
					return costs.values.reduce(0, combine: +)
				}
			}
		}
		switch self {
		case let .Pure(b):
			return b

		case let .Roll(.Recursive(a, b, f)):
			// Recur structurally into both terms, if compatible, patching paired sub-terms. This is akin to the shape of unification, except that it computes a patched tree instead of a substitution. It’s also a little like a structural zip on the pair of terms.
			//
			// At the moment, there are no restrictions on whether terms are compatible.
			if equals(a, b) { return f(Diff(b)).evaluate(equals, recur: recur) }

			switch (a.unwrap, b.unwrap) {
			case let (.Indexed(a), .Indexed(b)) where a.count == b.count:
				return f(.Indexed(zip(a, b).map(recurOrReplace))).evaluate(equals, recur: recur)

			case let (.Keyed(a), .Keyed(b)) where Array(a.keys) == Array(b.keys):
				return f(.Keyed(Dictionary(elements: b.keys.map { ($0, recurOrReplace(a[$0]!, b[$0]!)) }))).evaluate(equals, recur: recur)

			default:
				// This must not call `recur` with `a` and `b`, as that would infinite loop if actually recursive.
				return f(Diff.Pure(.Replace(a, b))).evaluate(equals, recur: recur)
			}

		case let .Roll(.ByKey(a, b, f)):
			// Essentially [set reconciliation](https://en.wikipedia.org/wiki/Data_synchronization#Unordered_data) on the keys, followed by recurring into the values of the intersecting keys.
			let deleted = Set(a.keys).subtract(b.keys).map { ($0, Diff.Pure(Patch.Delete(a[$0]!))) }
			let inserted = Set(b.keys).subtract(a.keys).map { ($0, Diff.Pure(Patch.Insert(b[$0]!))) }
			let patched = Set(a.keys).intersect(b.keys).map { ($0, recurOrReplace(a[$0]!, b[$0]!)) }
			return f(Dictionary(elements: deleted + inserted + patched)).evaluate(equals, recur: recur)

		case let .Roll(.ByIndex(a, b, f)):
			return f(SES(a, b, cost: cost, recur: recur)).evaluate(equals, recur: recur)
		}
	}
}

extension Algorithm where Term: Equatable {
	public func evaluate(recur: (Term, Term) -> Diff?) -> Result {
		return evaluate(==, recur: recur)
	}
}

extension Algorithm where Result: FreeConvertible, Result.RollType == Term.LeafType, Result.PureType == Algorithm<Term, Result>.Patch {
	/// `Algorithm<Term, Diff>`s can be constructed from a pair of `Term`s using `ByKey` when `Keyed`, `ByIndex` when `Indexed`, and `Recursive` otherwise.
	public init(_ a: Term, _ b: Term) {
		switch (a.unwrap, b.unwrap) {
		case let (.Keyed(a), .Keyed(b)):
			self = .Roll(.ByKey(a, b, Syntax.Keyed >>> Free.Roll >>> Result.init >>> Pure))
		case let (.Indexed(a), .Indexed(b)):
			self = .Roll(.ByIndex(a, b, Syntax.Indexed >>> Free.Roll >>> Result.init >>> Pure))
		default:
			self = .Roll(.Recursive(a, b, Result.init >>> Algorithm.Pure))
		}
	}

	public func evaluate(equals: (Term, Term) -> Bool) -> Result {
		return evaluate(equals, recur: { Algorithm($0, $1).evaluate(equals).free })
	}

	public func evaluate<C>(equals: (Term, Term) -> Bool, categorize: Term -> Set<C>) -> Result {
		return evaluate(equals, recur: {
			let c0 = categorize($0)
			let c1 = categorize($1)
			return c0 == c1 || !categorize($0).intersect(categorize($1)).isEmpty
				? Algorithm($0, $1).evaluate(equals).free
				: nil
		})
	}
}

extension Algorithm where Term: Equatable, Result: FreeConvertible, Result.RollType == Term.LeafType, Result.PureType == Algorithm<Term, Result>.Patch {
	public func evaluate() -> Result {
		return evaluate(==)
	}
}

extension Algorithm where Term: Categorizable, Result: FreeConvertible, Result.RollType == Term.LeafType, Result.PureType == Algorithm<Term, Result>.Patch {
	public func evaluate(equals: (Term, Term) -> Bool) -> Result {
		return evaluate(equals, categorize: { $0.categories })
	}
}


extension Algorithm where Term: Categorizable, Term: Equatable, Result: FreeConvertible, Result.RollType == Term.LeafType, Result.PureType == Algorithm<Term, Result>.Patch {
	public func evaluate() -> Result {
		return evaluate(==, categorize: { $0.categories })
	}
}


import Prelude
