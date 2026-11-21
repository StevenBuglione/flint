"""Deterministic independent-sample bootstrap of the ratio of group medians.

Base/candidate CI measurements are consecutive blocks, not temporally paired
observations. This interval describes run-level sampling variation; it cannot
remove systematic thermal/load drift between blocks. Such drift invalidates the
experiment and requires an identified infrastructure cause before a rerun.
"""
import math,random,statistics

def finite_samples(values,minimum):
    if not isinstance(values,(list,tuple)) or len(values)<minimum or any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) or v<=0 for v in values):
        raise ValueError(f'need >= {minimum} finite, strictly positive observations')

def median_ratio_interval(new,old,replicates=10000):
    finite_samples(new,9);finite_samples(old,9)
    if type(replicates) is not int or replicates<1000:raise ValueError('need >= 1000 bootstrap replicates')
    rng=random.Random(20261121)
    medians=sorted(statistics.median(rng.choices(new,k=len(new)))/
                   statistics.median(rng.choices(old,k=len(old))) for _ in range(replicates))
    return statistics.median(new)/statistics.median(old),medians[int(replicates*.005)],medians[int(replicates*.995)]
