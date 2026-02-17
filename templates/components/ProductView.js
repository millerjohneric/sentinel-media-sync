import React from 'react';
export default function ProductView({children, title}) { return (<div className='shop-view'><h2>{title}</h2><div className='details'>{children}</div></div>); }
