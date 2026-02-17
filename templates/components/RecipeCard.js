import React from 'react';
export default function RecipeCard({children, title}) { return (<div className='recipe-card'><h1>{title}</h1><hr/>{children}</div>); }
