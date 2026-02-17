import React from 'react';
export default function GalleryView({children}) { return (<div className='gallery-grid' style={{display:'flex', flexWrap:'wrap'}}>{children}</div>); }
