function initialize!(integrator, cache::ABDF2ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::ABDF2ConstantCache, repeat_step=false)
  @unpack t,f,p = integrator
  @unpack dtₙ₋₁,nlsolver = cache
  alg = unwrap_alg(integrator, true)
  dtₙ, uₙ, uₙ₋₁, uₙ₋₂ = integrator.dt, integrator.u, integrator.uprev, integrator.uprev2

  # TODO: this doesn't look right
  if integrator.iter == 1 && !integrator.u_modified
    cache.dtₙ₋₁ = dtₙ
    cache.eulercache.nlsolver.method = DIRK
    perform_step!(integrator, cache.eulercache, repeat_step)
    cache.fsalfirstprev = integrator.fsalfirst
    return
  end

  fₙ₋₁ = integrator.fsalfirst
  ρ = dtₙ/dtₙ₋₁
  β₀ = 2//3
  β₁ = -(ρ-1)/3
  α₀ = 1
  α̂ = ρ^2/3
  α₁ = 1+α̂
  α₂ = -α̂

  markfirststage!(nlsolver)

  # initial guess
  if alg.extrapolant == :linear
    u = @.. uₙ₋₁ + dtₙ * fₙ₋₁
  else # :constant
    u = uₙ₋₁
  end
  nlsolver.z = u

  mass_matrix = f.mass_matrix

  if mass_matrix === I
    nlsolver.tmp = @.. ((dtₙ * β₁) * fₙ₋₁ + (α₁ * uₙ₋₁ + α₂ * uₙ₋₂)) / (dtₙ * β₀)
  else
    _tmp = mass_matrix * @.. (α₁ * uₙ₋₁ + α₂ * uₙ₋₂)
    nlsolver.tmp = @.. ((dtₙ * β₁) * fₙ₋₁ + _tmp) / (dtₙ * β₀)
  end
  nlsolver.γ = β₀
  nlsolver.α = α₀
  nlsolver.method = COEFFICIENT_MULTISTEP
  uₙ = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return

  integrator.fsallast = f(uₙ,p,t+dtₙ)
  integrator.destats.nf += 1

  if integrator.opts.adaptive
    tmp = integrator.fsallast - (1+dtₙ/dtₙ₋₁)*integrator.fsalfirst + (dtₙ/dtₙ₋₁)*cache.fsalfirstprev
    est = (dtₙ₋₁+dtₙ)/6 * tmp
    atmp = calculate_residuals(est, uₙ₋₁, uₙ, integrator.opts.abstol, integrator.opts.reltol,integrator.opts.internalnorm,t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  ################################### Finalize

  if integrator.EEst < one(integrator.EEst)
    cache.fsalfirstprev = integrator.fsalfirst
    cache.dtₙ₋₁ = dtₙ
  end

  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = uₙ
  return
end

function initialize!(integrator, cache::ABDF2Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = du_alias_or_new(cache.nlsolver, integrator.fsalfirst)
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # For the interpolation, needs k at the updated point
  integrator.destats.nf += 1
end

@muladd function perform_step!(integrator, cache::ABDF2Cache, repeat_step=false)
  @unpack t,dt,f,p = integrator
  #TODO: remove zₙ₋₁ from the cache
  @unpack atmp,dtₙ₋₁,zₙ₋₁,nlsolver = cache
  @unpack z,tmp,ztmp = nlsolver
  alg = unwrap_alg(integrator, true)
  uₙ,uₙ₋₁,uₙ₋₂,dtₙ = integrator.u,integrator.uprev,integrator.uprev2,integrator.dt

  if integrator.iter == 1 && !integrator.u_modified
    cache.dtₙ₋₁ = dtₙ
    cache.eulercache.nlsolver.method = DIRK
    perform_step!(integrator, cache.eulercache, repeat_step)
    cache.fsalfirstprev .= integrator.fsalfirst
    nlsolver.tmp = tmp
    return
  end

  fₙ₋₁ = integrator.fsalfirst
  ρ = dtₙ/dtₙ₋₁
  β₀ = 2//3
  β₁ = -(ρ-1)/3
  α₀ = 1
  α̂ = ρ^2/3
  α₁ = 1+α̂
  α₂ = -α̂

  markfirststage!(nlsolver)

  # initial guess
  if alg.extrapolant == :linear
    @.. z = uₙ₋₁ + dtₙ * fₙ₋₁
  else # :constant
    @.. z = uₙ₋₁
  end

  mass_matrix = f.mass_matrix

  if mass_matrix === I
    @.. tmp = ((dtₙ * β₁) * fₙ₋₁ + (α₁ * uₙ₋₁ + α₂ * uₙ₋₂)) / (dtₙ * β₀)
  else
    dz = nlsolver.cache.dz
    @.. dz = α₁ * uₙ₋₁ + α₂ * uₙ₋₂
    mul!(ztmp, mass_matrix, dz)
    @.. tmp = ((dtₙ * β₁) * fₙ₋₁ + ztmp) / (dtₙ * β₀)
  end
  nlsolver.γ = β₀
  nlsolver.α = α₀
  nlsolver.method = COEFFICIENT_MULTISTEP
  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return

  @.. uₙ = z

  f(integrator.fsallast, uₙ, p, t+dtₙ)
  integrator.destats.nf += 1
  if integrator.opts.adaptive
    btilde0 = (dtₙ₋₁+dtₙ)*1//6
    btilde1 = 1+dtₙ/dtₙ₋₁
    btilde2 = dtₙ/dtₙ₋₁
    @.. tmp = btilde0*(integrator.fsallast - btilde1*integrator.fsalfirst + btilde2*cache.fsalfirstprev)
    calculate_residuals!(atmp, tmp, uₙ₋₁, uₙ, integrator.opts.abstol, integrator.opts.reltol,integrator.opts.internalnorm,t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  ################################### Finalize

  if integrator.EEst < one(integrator.EEst)
    @.. cache.fsalfirstprev = integrator.fsalfirst
    cache.dtₙ₋₁ = dtₙ
  end
  return
end

# SBDF

function initialize!(integrator, cache::SBDFConstantCache)
  @unpack uprev, p, t = integrator
  @unpack f1, f2 = integrator.f
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  cache.du₁ = f1(uprev,p,t)
  cache.du₂ = f2(uprev,p,t)
  integrator.destats.nf += 1
  integrator.destats.nf2 += 1
  integrator.fsalfirst = cache.du₁ + cache.du₂

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::SBDFConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p,alg = integrator
  @unpack uprev2,uprev3,uprev4,du₁,du₂,k₁,k₂,k₃,nlsolver = cache
  @unpack f1, f2 = integrator.f
  cnt = cache.cnt = min(alg.order, integrator.iter+1)
  integrator.iter == 1 && !integrator.u_modified && ( cnt = cache.cnt = 1 )
  nlsolver.γ = γ = inv(γₖ[cnt])
  if cnt == 1
    tmp = uprev + dt*du₂
  elseif cnt == 2
    tmp = γ * (2*uprev - 1//2*uprev2 + dt*(2*du₂ - k₁))
  elseif cnt == 3
    tmp = γ * (3*uprev - 3//2*uprev2 + 1//3*uprev3 + dt*(3*(du₂ - k₁) + k₂))
  else
    tmp = γ * (4*uprev - 3*uprev2 + 4//3*uprev3 - 1//4*uprev4 + dt*(4*du₂ - 6*k₁ + 4*k₂ - k₃))
  end
  nlsolver.tmp = tmp

  # Implicit part
  # precalculations
  γdt = γ*dt
  markfirststage!(nlsolver)

  # initial guess
  if alg.extrapolant == :linear
    z = dt*du₁
  else # :constant
    z = zero(u)
  end
  nlsolver.z = z

  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return
  u = nlsolver.tmp + γ*z

  cnt == 4 && ( cache.uprev4 = uprev3; cache.k₃ = k₂ )
  cnt >= 3 && ( cache.uprev3 = uprev2; cache.k₂ = k₁ )
              ( cache.uprev2 = uprev;  cache.k₁ = du₂ )
  cache.du₁ = f1(u, p, t+dt)
  cache.du₂ = f2(u, p, t+dt)
  integrator.destats.nf += 1
  integrator.destats.nf2 += 1
  integrator.fsallast = cache.du₁ + cache.du₂
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator, cache::SBDFCache)
  @unpack uprev, p, t = integrator
  @unpack f1, f2 = integrator.f
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = du_alias_or_new(cache.nlsolver, integrator.fsalfirst)
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  f1(cache.du₁, uprev, p, t)
  f2(cache.du₂, uprev, p, t)
  integrator.destats.nf += 1
  integrator.destats.nf2 += 1
  @.. integrator.fsalfirst = cache.du₁ + cache.du₂
end

function perform_step!(integrator, cache::SBDFCache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p,alg = integrator
  @unpack uprev2,uprev3,uprev4,k₁,k₂,k₃,du₁,du₂,nlsolver = cache
  @unpack tmp,z = nlsolver
  @unpack f1, f2 = integrator.f
  cnt = cache.cnt = min(alg.order, integrator.iter+1)
  integrator.iter == 1 && !integrator.u_modified && ( cnt = cache.cnt = 1 )
  nlsolver.γ = γ = inv(γₖ[cnt])
  # Explicit part
  if cnt == 1
    @.. tmp = uprev + dt*du₂
  elseif cnt == 2
    @.. tmp = γ * (2*uprev - 1//2*uprev2 + dt*(2*du₂ - k₁))
  elseif cnt == 3
    @.. tmp = γ * (3*uprev - 3//2*uprev2 + 1//3*uprev3 + dt*(3*(du₂ - k₁) + k₂))
  else
    @.. tmp = γ * (4*uprev - 3*uprev2 + 4//3*uprev3 - 1//4*uprev4 + dt*(4*du₂ - 6*k₁ + 4*k₂ - k₃))
  end
  # Implicit part
  # precalculations
  γdt = γ*dt
  markfirststage!(nlsolver)

  # initial guess
  if alg.extrapolant == :linear
    @.. z = dt*du₁
  else # :constant
    @.. z = zero(eltype(u))
  end

  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return
  @.. u = tmp + γ*z

  cnt == 4 && ( cache.uprev4 .= uprev3; cache.k₃ .= k₂ )
  cnt >= 3 && ( cache.uprev3 .= uprev2; cache.k₂ .= k₁ )
              ( cache.uprev2 .= uprev;  cache.k₁ .= du₂ )
  f1(du₁, u, p, t+dt)
  f2(du₂, u, p, t+dt)
  integrator.destats.nf += 1
  integrator.destats.nf2 += 1
  @.. integrator.fsallast = du₁ + du₂
end

# QNDF1

function initialize!(integrator, cache::QNDF1ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::QNDF1ConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack uprev2,D,D2,R,U,dtₙ₋₁,nlsolver = cache
  alg = unwrap_alg(integrator, true)
  κ = alg.kappa
  cnt = integrator.iter
  k = 1
  if cnt > 1
    ρ = dt/dtₙ₋₁
    D[1] = uprev - uprev2   # backward diff
    if ρ != 1
      R!(k,ρ,cache)
      R .= R * U
      D[1] = D[1] * R[1,1]
    end
  else
    κ = zero(alg.kappa)
  end

  #Changing uprev2 after D Array has changed with step-size
  uprev2 = uprev-D[1]

  β₀ = 1 
  α₀ = 1-κ
  α₁ = 1-2*κ
  α₂ = κ

  markfirststage!(nlsolver)

  # initial guess
  nlsolver.z = uprev + sum(D)

  mass_matrix = f.mass_matrix

  if mass_matrix === I
    nlsolver.tmp = @.. (α₁ * uprev + α₂ * uprev2) / (dt * β₀)
  else
    _tmp = mass_matrix * @.. (α₁ * uprev + α₂ * uprev2)
    nlsolver.tmp = @.. _tmp / (dt * β₀)
  end

  nlsolver.γ = β₀
  nlsolver.α = α₀
  nlsolver.method = COEFFICIENT_MULTISTEP

  u = nlsolve!(nlsolver, integrator, cache, repeat_step)

  nlsolvefail(nlsolver) && return
  if integrator.opts.adaptive 
    if integrator.success_iter == 0
      integrator.EEst = one(integrator.EEst)
    else
      D2[1] = u - uprev
      D2[2] = D2[1] - D[1]
      utilde = (κ + inv(k+1)) * D2[2]
      atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(atmp,t)
    end
  end
  if integrator.EEst > one(integrator.EEst)
    return
  end
  cache.dtₙ₋₁ = dt
  cache.uprev2 = uprev
  integrator.fsallast = f(u, p, t+dt)
  integrator.destats.nf += 1
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
  return
end

function initialize!(integrator, cache::QNDF1Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = du_alias_or_new(cache.nlsolver, integrator.fsalfirst)
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # For the interpolation, needs k at the updated point
  integrator.destats.nf += 1
end

function perform_step!(integrator,cache::QNDF1Cache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack uprev2,D,D2,R,U,dtₙ₋₁,utilde,atmp,nlsolver = cache
  @unpack z,tmp,ztmp = nlsolver
  alg = unwrap_alg(integrator, true)
  κ = alg.kappa
  cnt = integrator.iter
  k = 1
  if cnt > 1
    ρ = dt/dtₙ₋₁
    @.. D[1] = uprev - uprev2 # backward diff
    if ρ != 1
      R!(k,ρ,cache)
      R .= R * U
      @.. D[1] = D[1] * R[1,1]
    end
  else
    κ = zero(alg.kappa)
  end

  #Changing uprev2 after D Array has changed with step-size
  uprev2 = uprev - D[1]
    
  β₀ = 1 
  α₀ = 1-κ
  α₁ = 1-2*κ
  α₂ = κ

  markfirststage!(nlsolver)

  # initial guess
  nlsolver.z = uprev + sum(D)

  mass_matrix = f.mass_matrix

  if mass_matrix === I
    @.. tmp = (α₁ * uprev + α₂ * uprev2) / (dt * β₀)
  else
    dz = nlsolver.cache.dz
    @.. dz = α₁ * uprev + α₂ * uprev2
    mul!(ztmp, mass_matrix, dz)
    @.. tmp = ztmp / (dt * β₀)
  end

  nlsolver.γ = β₀
  nlsolver.α = α₀
  nlsolver.method = COEFFICIENT_MULTISTEP
  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return
  @.. u = z

  if integrator.opts.adaptive
    if integrator.success_iter == 0
      integrator.EEst = one(integrator.EEst)
    else
      @.. D2[1] = u - uprev
      @.. D2[2] = D2[1] - D[1]
      @.. utilde = (κ + inv(k+1)) * D2[2]
      calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(atmp,t)
    end
  end
  if integrator.EEst > one(integrator.EEst)
    return
  end
  cache.uprev2 .= uprev
  cache.dtₙ₋₁ = dt
  f(integrator.fsallast, u, p, t+dt)
  integrator.destats.nf += 1
  return
end

function initialize!(integrator, cache::QNDF2ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::QNDF2ConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack uprev2,uprev3,dtₙ₋₁,dtₙ₋₂,D,D2,R,U,nlsolver = cache
  alg = unwrap_alg(integrator, true)
  cnt = integrator.iter
  k = 2
  if cnt == 1 || cnt == 2
    κ = zero(alg.kappa)
    γ₁ = 1//1
    γ₂ = 1//1
  elseif dtₙ₋₁ != dtₙ₋₂
    κ = alg.kappa
    γ₁ = 1//1
    γ₂ = 1//1 + 1//2
    ρ₁ = dt/dtₙ₋₁
    ρ₂ = dt/dtₙ₋₂
    D[1] = uprev - uprev2
    D[1] = D[1] * ρ₁
    D[2] = D[1] - ((uprev2 - uprev3) * ρ₂)
  else
    κ = alg.kappa
    γ₁ = 1//1
    γ₂ = 1//1 + 1//2
    ρ = dt/dtₙ₋₁
    # backward diff
    D[1] = uprev - uprev2
    D[2] = D[1] - (uprev2 - uprev3)
    if ρ != 1
      R!(k,ρ,cache)
      R .= R * U
      D[1] = D[1] * R[1,1] + D[2] * R[2,1]
      D[2] = D[1] * R[1,2] + D[2] * R[2,2]
    end
  end

  β₀ = inv((1-κ)*γ₂)
  α₀ = 1

  u₀ = uprev + D[1] + D[2]
  ϕ = (γ₁*D[1] + γ₂*D[2])*β₀

  markfirststage!(nlsolver)

  # initial guess
  nlsolver.z = uprev + sum(D)

  mass_matrix = f.mass_matrix

  if mass_matrix === I
    nlsolver.tmp = @.. (u₀ - ϕ)/ (dt * β₀)
  else
    _tmp = mass_matrix * @.. (u₀ - ϕ)
    nlsolver.tmp = @.. _tmp / (dt * β₀)
  end

  nlsolver.γ = β₀
  nlsolver.α = α₀
  nlsolver.method = COEFFICIENT_MULTISTEP

  u = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return

  if integrator.opts.adaptive
    if integrator.success_iter == 0
      integrator.EEst = one(integrator.EEst)
    elseif integrator.success_iter == 1
      utilde = (u - uprev) - ((uprev - uprev2) * dt/dtₙ₋₁)
      atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(atmp,t)
    else
      D2[1] = u - uprev
      D2[2] = D2[1] - D[1]
      D2[3] = D2[2] - D[2]
      utilde = (κ*γ₂ + inv(k+1)) * D2[3]
      atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(atmp,t)
    end
  end
  if integrator.EEst > one(integrator.EEst)
    return
  end

  cache.uprev3 = uprev2
  cache.uprev2 = uprev
  cache.dtₙ₋₂ = dtₙ₋₁
  cache.dtₙ₋₁ = dt
  integrator.fsallast = f(u, p, t+dt)
  integrator.destats.nf += 1
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
  return
end

function initialize!(integrator, cache::QNDF2Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = du_alias_or_new(cache.nlsolver, integrator.fsalfirst)
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # For the interpolation, needs k at the updated point
  integrator.destats.nf += 1
end

function perform_step!(integrator,cache::QNDF2Cache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack uprev2,uprev3,dtₙ₋₁,dtₙ₋₂,D,D2,R,U,utilde,atmp,nlsolver = cache
  @unpack z,tmp,ztmp = nlsolver
  alg = unwrap_alg(integrator, true)
  cnt = integrator.iter
  k = 2
  if cnt == 1 || cnt == 2
    κ = zero(alg.kappa)
    γ₁ = 1//1
    γ₂ = 1//1
  elseif dtₙ₋₁ != dtₙ₋₂
    κ = alg.kappa
    γ₁ = 1//1
    γ₂ = 1//1 + 1//2
    ρ₁ = dt/dtₙ₋₁
    ρ₂ = dt/dtₙ₋₂
    @.. D[1] = uprev - uprev2
    @.. D[1] = D[1] * ρ₁
    @.. D[2] = D[1] - ((uprev2 - uprev3) * ρ₂)
  else
    κ = alg.kappa
    γ₁ = 1//1
    γ₂ = 1//1 + 1//2
    ρ = dt/dtₙ₋₁
    # backward diff
    @.. D[1] = uprev - uprev2
    @.. D[2] = D[1] - (uprev2 - uprev3)
    if ρ != 1
      R!(k,ρ,cache)
      R .= R * U
      @.. D[1] = D[1] * R[1,1] + D[2] * R[2,1]
      @.. D[2] = D[1] * R[1,2] + D[2] * R[2,2]
    end
  end

  β₀ = inv((1-κ)*γ₂)
  α₀ = 1

  u₀ = uprev + D[1] + D[2]
  ϕ = (γ₁*D[1] + γ₂*D[2])*β₀

  markfirststage!(nlsolver)

  # initial guess
  nlsolver.z = uprev + sum(D)

  mass_matrix = f.mass_matrix

  if mass_matrix === I
    @.. tmp =  (u₀ - ϕ)/ (dt * β₀)
  else
    dz = nlsolver.cache.dz
    @.. dz = u₀ - ϕ
    mul!(ztmp, mass_matrix, dz)
    @.. tmp = ztmp / (dt * β₀)
  end

  nlsolver.γ = β₀
  nlsolver.α = α₀
  nlsolver.method = COEFFICIENT_MULTISTEP

  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return
  @.. u = z

  if integrator.opts.adaptive
    if integrator.success_iter == 0
      integrator.EEst = one(integrator.EEst)
    elseif integrator.success_iter == 1
      @.. utilde = (u - uprev) - ((uprev - uprev2) * dt/dtₙ₋₁)
      calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(atmp,t)
    else
      @.. D2[1] = u - uprev
      @.. D2[2] = D2[1] - D[1]
      @.. D2[3] = D2[2] - D[2]
      @.. utilde = (κ*γ₂ + inv(k+1)) * D2[3]
      calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(atmp,t)
    end
  end
  if integrator.EEst > one(integrator.EEst)
    return
  end

  cache.uprev3 .= uprev2
  cache.uprev2 .= uprev
  cache.dtₙ₋₂ = dtₙ₋₁
  cache.dtₙ₋₁ = dt
  f(integrator.fsallast, u, p, t+dt)
  integrator.destats.nf += 1
  return
end

function initialize!(integrator, cache::QNDFConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::QNDFConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p,iter = integrator
  @unpack dtprev,order,nconsteps,max_order,D,prevD,R,nlsolver,γₖ = cache
  if dt!=dtprev && dtprev!=0
    cache.changed=true
  end
  k = order
  κlist = integrator.alg.kappa
  κ = κlist[k]
  #@show nconsteps, D
  #κlist = zeros(5)
  #κ = 0
  #=if 45<iter<68
    @show D
    @show prevD
    @show dt,dtprev,cache.consfailcnt
  end=#
  if cache.consfailcnt>0
    #@show cache.D
    D = copy(cache.prevD)
  end
  #if nconsteps > cache.prevorder+1 || cache.changed == true
  if cache.changed && dtprev!=0
    #@info nconsteps
    ρ = dt/dtprev
    #@info ρ
    if ρ != 1 #|| k != cache.prevorder
      #@show nconsteps
      integrator.cache.nconsteps = 0
      @unpack U,R = cache
      calc_R!(R,ρ,Val(k))
      RU = zeros(k,k)
      @views mul!(RU,R[1:k,1:k],U[1:k,1:k])
      Dtmp = similar(D[:,1:k])
      mul!(Dtmp,D[:,1:k],RU)
      copyto!(D, Dtmp)
    end
  end

  #if cache.consfailcnt == 0
  #  cache.dtprev = dt
  #end
  ##precalculations:
  α₀ = 1
  β₀ = inv((1-κ)*γₖ[k])
  if u isa Number
    @views u₀ = sum(D[1:k]) + uprev  # u₀ is predicted value
    ϕ = zero(u)
    for i = 1:k
      ϕ += γₖ[i]*D[i]
    end
  else
    u₀ = reshape(sum(D[:,1:k],dims=2) .+ uprev, size(u))  # u₀ is predicted value
    ϕ = zero(u)
    for i = 1:k
      @views @.. ϕ += γₖ[i]*D[:,i]
    end
  end
  markfirststage!(nlsolver)
  nlsolver.z = u₀
  mass_matrix = f.mass_matrix

  if mass_matrix == I
    #nlsolver.tmp = @.. u₀*inv(β₀*dt)-ϕ*inv(dt)
    nlsolver.tmp = @.. (u₀/β₀-ϕ)/dt
    #nlsolver.tmp = uprev*inv(dt)
  else
    nlsolver.tmp = mass_matrix * @.. (u₀/β₀-ϕ)/dt
  end

  ###nlsolve:
  nlsolver.γ = β₀
  nlsolver.α = α₀
  nlsolver.method = COEFFICIENT_MULTISTEP

  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return
  u = z
  dd = u-u₀
  update_D!(dd,D,k)
  #@info cache.D

  if integrator.opts.adaptive 
    utilde = (κ*γₖ[k]+inv(k+1))*dd
    atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
    #integrator.EEst = integrator.opts.internalnorm(utilde,t)/integrator.opts.reltol
    #integrator.EEst = integrator.opts.internalnorm(utilde,t)/integrator.opts.reltol
    if k >1
      dd = D[k]
      utildem1 = (κlist[k-1]*γₖ[k-1]+inv(k))*dd
      atmpm1 = calculate_residuals(utildem1, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      cache.EEst1 = integrator.opts.internalnorm(atmpm1, t)
      #cache.EEst1 = integrator.opts.internalnorm(utildem1, t)/integrator.opts.reltol
    end
    if k < cache.max_order
      dd = D[k+2]
      utildep1 = (κlist[k+1]*γₖ[k+1]+inv(k+2))*dd
      atmpp1 = calculate_residuals(utildep1, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      cache.EEst2 = integrator.opts.internalnorm(atmpp1, t)
      #cache.EEst2 = integrator.opts.internalnorm(utildep1, t)/integrator.opts.reltol
    end
  end
  if integrator.EEst <= 1.0
    #cache.u₀ = u₀
    cache.prevorder = k
    cache.prevD = copy(D)
    cache.dtprev = dt
    cache.D = D
  end
  #=if 42<iter<68
    #@info integrator.EEst, k, cache.nconsteps
    #@show 22222222
    ##@show D
    #@warn cache.D
  end=#
  integrator.fsallast = f(u, p, t+dt)
  #@show u-(uprev+dt*integrator.fsallast), k
  integrator.destats.nf += 1
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator, cache::QNDFCache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = du_alias_or_new(cache.nlsolver, integrator.fsalfirst)
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # For the interpolation, needs k at the updated point
  integrator.destats.nf += 1
end

function perform_step!(integrator, cache::QNDFCache{max_order}, repeat_step=false) where max_order
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack dtprev,order,D,nlsolver,γₖ = cache

  if dt != dtprev && dtprev != 0
    cache.changed=true
  end
  k = order
  κlist = integrator.alg.kappa
  κ = κlist[k]
  # i (accept)            i+1 (reject)                       i+2
  #   dt_{i}     dt_{i+1} ρ = dt_{i+1}/dt_{i}    dt_{i+1} ρ = dt_{i+2} / dt_{i+1}
  if cache.consfailcnt > 0
    D = copy(cache.prevD)
  end

  if cache.changed && dtprev!=0
    ρ = dt/dtprev # this is pretty minor, but you should check `dt == dtprev` first, then compute `rho`, because division is more expensive than comparesion, so we want to minimize the number of floating point number divisions.
    if ρ != 1
      integrator.cache.nconsteps = 0
      @unpack RU, U, Dtmp = cache
      R = calc_R(ρ, k, Val(max_order))
      copyto!(RU, R * U)
      @views mul!(Dtmp[:, 1:k], D[:, 1:k], RU[1:k, 1:k])
      D, Dtmp = Dtmp, D
      @pack! cache = D, Dtmp
    end
  end

  α₀ = 1
  β₀ = inv((1-κ)*γₖ[k])
  # cache the `sum(D[:,1:k], dims=2)`. Write the loop yourself, since `sum` allocates intermediate arrays to accumulate into.
  u₀ = reshape(sum(D[:,1:k], dims=2) .+ uprev, size(u))  # u₀ is predicted value
  ϕ = zero(u) # use cache
  for i = 1:k
    @views @.. ϕ += γₖ[i] * D[:, i]
  end
  markfirststage!(nlsolver)
  @.. nlsolver.z = u₀
  mass_matrix = f.mass_matrix

  if mass_matrix == I
    @.. nlsolver.tmp = (u₀/β₀-ϕ)/dt # loop fusion
  else
    @.. nlsolver.tmp = mass_matrix * (u₀/β₀-ϕ)/dt # this is wrong. @.. broadcasts all the expression after it, but we need `mass_matrix * v` to be a matrix-vector product.
    # try something like
    # ```julia
    # @. tmp2 = (u₀/β₀-ϕ)/dt
    # mul!(nlsolver.tmp, mass_matrix, tmp2)
    # ```
  end

  nlsolver.γ = β₀
  nlsolver.α = α₀
  nlsolver.method = COEFFICIENT_MULTISTEP

  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return
  @.. u = z
  dd = u-u₀  # TODO: cache
  update_D!(dd, D, k) # TODO: the signature should be (D, dd, k)

  # Tsit5 (in-place)
  if integrator.opts.adaptive 
    utilde = (κ*γₖ[k]+inv(k+1))*dd # TODO: use `utilde` in cache
    calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t) # TODO: use `calculate_residual!`
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
    if k > 1
      dd = D[k]
      utildem1 = (κlist[k-1]*γₖ[k-1]+inv(k))*dd # TODO: same as the above
      atmpm1 = calculate_residuals(utildem1, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      cache.EEst1 = integrator.opts.internalnorm(atmpm1, t)
    end
    if k < max_order
      dd = D[k+2]
      utildep1 = (κlist[k+1]*γₖ[k+1]+inv(k+2))*dd # TODO: same as the above
      atmpp1 = calculate_residuals(utildep1, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      cache.EEst2 = integrator.opts.internalnorm(atmpp1, t)
    end
  end
  if integrator.EEst <= 1.0
    cache.prevorder = k
    cache.prevD = copy(D) # TODO: remove prevD
    cache.dtprev = dt # TODO: should always cache dt, even if the step is rejected. [Maybe?] Also, be careful when Newton diverges. It returns earily in the `perform_step!` function.
    cache.D = D # WUT
  end

  f(integrator.fsallast, u, p, t+dt)
  integrator.destats.nf += 1
  return nothing
end

### MEBDF2
function initialize!(integrator, cache::MEBDF2ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::MEBDF2ConstantCache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  nlsolver = cache.nlsolver
  alg = unwrap_alg(integrator, true)
  markfirststage!(nlsolver)

  # initial guess
  if alg.extrapolant == :linear
    nlsolver.z = dt*integrator.fsalfirst
  else # :constant
    nlsolver.z = zero(u)
  end

### STEP 1
  nlsolver.tmp = uprev
  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return
  z₁ = nlsolver.tmp + z
### STEP 2
  nlsolver.tmp = z₁
  nlsolver.c = 2
  isnewton(nlsolver) && set_new_W!(nlsolver, false)
  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return
  z₂ = z₁ + z
### STEP 3
  tmp2 = 0.5uprev + z₁ - 0.5z₂
  nlsolver.tmp = tmp2
  nlsolver.c = 1
  isnewton(nlsolver) && set_new_W!(nlsolver, false)
  z = nlsolve!(nlsolver, integrator, cache, repeat_step)
  nlsolvefail(nlsolver) && return
  u = tmp2 + z

### finalize
  integrator.fsallast = f(u, p, t+dt)
  integrator.destats.nf += 1
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator, cache::MEBDF2Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = du_alias_or_new(cache.nlsolver, integrator.fsalfirst)
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # For the interpolation, needs k at the updated point
  integrator.destats.nf += 1
end

@muladd function perform_step!(integrator, cache::MEBDF2Cache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack z₁,z₂,tmp2,nlsolver = cache
  z = nlsolver.z
  mass_matrix = integrator.f.mass_matrix
  alg = unwrap_alg(integrator, true)
  markfirststage!(nlsolver)

  # initial guess
  if alg.extrapolant == :linear
    @.. z = dt*integrator.fsalfirst
  else # :constant
    z .= zero(eltype(u))
  end

### STEP 1
 nlsolver.tmp = uprev
 z = nlsolve!(nlsolver, integrator, cache, repeat_step)
 nlsolvefail(nlsolver) && return
 @.. z₁ = uprev + z
### STEP 2
 nlsolver.tmp = z₁
 nlsolver.c = 2
 isnewton(nlsolver) && set_new_W!(nlsolver, false)
 z = nlsolve!(nlsolver, integrator, cache, repeat_step)
 nlsolvefail(nlsolver) && return
 @.. z₂ = z₁ + z
### STEP 3
 # z .= zero(eltype(u))
 @.. tmp2 = 0.5uprev + z₁ - 0.5z₂
 nlsolver.tmp = tmp2
 nlsolver.c = 1
 isnewton(nlsolver) && set_new_W!(nlsolver, false)
 z = nlsolve!(nlsolver, integrator, cache, repeat_step)
 nlsolvefail(nlsolver) && return
 @.. u = tmp2 + z

### finalize
 f(integrator.fsallast,u,p,t+dt)
 integrator.destats.nf += 1
end
